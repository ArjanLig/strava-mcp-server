"""Tests for training load calculation functions in server.py."""

import sys
import os
from dataclasses import dataclass
from datetime import datetime, timedelta

import pytest

# Add project root to path so we can import server functions
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from server import (
    calculate_training_loads,
    get_training_recommendation,
    calculate_weekly_trends,
    calculate_ramp_rate,
    generate_weekly_recommendation,
)


@dataclass
class MockActivity:
    """Minimal activity object with the fields training load functions need."""
    start_date_local: datetime
    suffer_score: int | None


def make_activities(day_scores: dict[int, int]) -> list[MockActivity]:
    """Create mock activities from a {days_ago: suffer_score} mapping."""
    now = datetime.now()
    return [
        MockActivity(
            start_date_local=now - timedelta(days=d),
            suffer_score=score,
        )
        for d, score in day_scores.items()
    ]


# ── calculate_training_loads ──────────────────────────────────────────


class TestCalculateTrainingLoads:
    def test_no_activities(self):
        result = calculate_training_loads([])
        assert result["atl"] == 0
        assert result["ctl"] == 0
        assert result["tsb"] == 0

    def test_single_activity_today(self):
        activities = make_activities({0: 70})
        result = calculate_training_loads(activities)
        assert result["atl"] == round(70 / 7, 1)  # 10.0
        assert result["ctl"] == round(70 / 42, 1)  # 1.7

    def test_activities_beyond_ctl_window_excluded(self):
        # Activity 50 days ago should be excluded (> 42 day default)
        activities = make_activities({50: 100})
        result = calculate_training_loads(activities)
        assert result["atl"] == 0
        assert result["ctl"] == 0

    def test_atl_higher_than_ctl_gives_negative_tsb(self):
        # Heavy recent load, nothing older
        activities = make_activities({0: 100, 1: 100, 2: 100})
        result = calculate_training_loads(activities)
        assert result["atl"] > result["ctl"]
        assert result["tsb"] < 0

    def test_none_suffer_score_treated_as_zero(self):
        activities = [
            MockActivity(start_date_local=datetime.now(), suffer_score=None)
        ]
        result = calculate_training_loads(activities)
        assert result["atl"] == 0

    def test_multiple_activities_same_day_summed(self):
        now = datetime.now()
        activities = [
            MockActivity(start_date_local=now, suffer_score=30),
            MockActivity(start_date_local=now, suffer_score=20),
        ]
        result = calculate_training_loads(activities)
        assert result["atl"] == round(50 / 7, 1)

    def test_daily_loads_returned(self):
        activities = make_activities({0: 50, 3: 40})
        result = calculate_training_loads(activities)
        assert len(result["daily_loads"]) == 2


# ── get_training_recommendation ───────────────────────────────────────


class TestGetTrainingRecommendation:
    @pytest.mark.parametrize(
        "tsb, expected_keyword",
        [
            (-35, "REST"),
            (-15, "EASY"),
            (0, "MODERATE"),
            (10, "HARD"),
            (30, "DETRAINING"),
        ],
    )
    def test_tsb_zones(self, tsb, expected_keyword):
        result = get_training_recommendation(tsb, atl=20, ctl=20)
        assert expected_keyword in result["status"]

    @pytest.mark.parametrize(
        "ctl, expected_fragment",
        [
            (10, "low"),
            (45, "solid"),
            (80, "high"),
        ],
    )
    def test_fitness_levels(self, ctl, expected_fragment):
        result = get_training_recommendation(tsb=0, atl=20, ctl=ctl)
        assert expected_fragment in result["fitness_context"].lower()

    def test_returns_all_keys(self):
        result = get_training_recommendation(tsb=0, atl=20, ctl=40)
        assert set(result.keys()) == {"status", "advice", "intensity", "fitness_context"}


# ── calculate_weekly_trends ───────────────────────────────────────────


class TestCalculateWeeklyTrends:
    def test_empty_loads(self):
        trends = calculate_weekly_trends({}, weeks=4)
        assert len(trends) == 4
        assert all(t["atl"] == 0 for t in trends)

    def test_returns_oldest_first(self):
        trends = calculate_weekly_trends({}, weeks=4)
        assert trends[0]["week_label"].startswith("Week -")
        assert trends[-1]["week_label"] == "This week"

    def test_recent_load_appears_in_current_week(self):
        today = datetime.now().date()
        daily_loads = {today: 70}
        trends = calculate_weekly_trends(daily_loads, weeks=2)
        current = trends[-1]
        assert current["atl"] == round(70 / 7, 1)

    def test_tsb_equals_ctl_minus_atl(self):
        trends = calculate_weekly_trends({}, weeks=2)
        for t in trends:
            assert t["tsb"] == round(t["ctl"] - t["atl"], 1)


# ── calculate_ramp_rate ───────────────────────────────────────────────


class TestCalculateRampRate:
    def test_too_few_weeks_returns_none(self):
        assert calculate_ramp_rate([]) is None
        assert calculate_ramp_rate([{"atl": 10}]) is None

    def test_zero_previous_atl_returns_none(self):
        trends = [{"atl": 0}, {"atl": 10}]
        assert calculate_ramp_rate(trends) is None

    @pytest.mark.parametrize(
        "prev, curr, expected_keyword",
        [
            (10, 12.0, "TOO FAST"),    # +20%
            (10, 11.2, "FAST"),        # +12%
            (10, 10.7, "GOOD"),        # +7%
            (10, 10.0, "STABLE"),      # 0%
            (10, 9.0, "DECLINING"),    # -10%
        ],
    )
    def test_ramp_rate_zones(self, prev, curr, expected_keyword):
        trends = [{"atl": prev}, {"atl": curr}]
        result = calculate_ramp_rate(trends)
        assert expected_keyword in result["status"]

    def test_returns_all_keys(self):
        trends = [{"atl": 10}, {"atl": 11}]
        result = calculate_ramp_rate(trends)
        assert set(result.keys()) == {"rate", "status", "warning", "current_atl", "previous_atl"}


# ── generate_weekly_recommendation ────────────────────────────────────


class TestGenerateWeeklyRecommendation:
    def test_high_ramp_rate_reduces_volume(self):
        ramp = {"rate": 15, "status": "TOO FAST", "warning": "x", "current_atl": 10, "previous_atl": 8}
        result = generate_weekly_recommendation(tsb=0, atl=20, ctl=20, ramp_rate_data=ramp)
        assert "Reduce" in result["volume_advice"]
        assert result["target_hours"] < result["current_hours"]

    def test_very_fatigued_reduces_volume_30pct(self):
        result = generate_weekly_recommendation(tsb=-35, atl=20, ctl=20, ramp_rate_data=None)
        assert "30%" in result["volume_advice"]

    def test_fatigued_reduces_volume_15pct(self):
        result = generate_weekly_recommendation(tsb=-15, atl=20, ctl=20, ramp_rate_data=None)
        assert "15%" in result["volume_advice"]

    def test_fresh_increases_volume(self):
        result = generate_weekly_recommendation(tsb=20, atl=20, ctl=20, ramp_rate_data=None)
        assert "Increase" in result["volume_advice"]
        assert result["target_hours"] > result["current_hours"]

    def test_balanced_maintains_volume(self):
        result = generate_weekly_recommendation(tsb=0, atl=20, ctl=20, ramp_rate_data=None)
        assert "Maintain" in result["volume_advice"]

    def test_plan_has_workout_types(self):
        result = generate_weekly_recommendation(tsb=0, atl=20, ctl=20, ramp_rate_data=None)
        assert isinstance(result["plan"], dict)
        assert sum(result["plan"].values()) == 7  # 7 days

    def test_rest_plan_has_no_intervals(self):
        result = generate_weekly_recommendation(tsb=-35, atl=20, ctl=20, ramp_rate_data=None)
        assert result["plan"].get("intervals", 0) == 0

    def test_fresh_plan_has_intervals(self):
        result = generate_weekly_recommendation(tsb=20, atl=20, ctl=20, ramp_rate_data=None)
        assert result["plan"].get("intervals", 0) > 0

    def test_returns_all_keys(self):
        result = generate_weekly_recommendation(tsb=0, atl=20, ctl=20, ramp_rate_data=None)
        assert set(result.keys()) == {"target_hours", "current_hours", "volume_advice", "plan", "intensity_note"}
