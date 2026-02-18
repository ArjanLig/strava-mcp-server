import os
import asyncio
from datetime import datetime, timedelta
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent
from stravalib.client import Client
from dotenv import load_dotenv

# Laad credentials
load_dotenv()


# Initialiseer Strava client met auto-refresh
def get_authenticated_client():
    """Maak authenticated client met auto token refresh"""
    client = Client()

    access_token = os.getenv('STRAVA_ACCESS_TOKEN')
    refresh_token = os.getenv('STRAVA_REFRESH_TOKEN')
    client_id = os.getenv('STRAVA_CLIENT_ID')
    client_secret = os.getenv('STRAVA_CLIENT_SECRET')

    # Probeer eerst met access token
    client.access_token = access_token

    # Check of token nog geldig is door een test request
    try:
        # Simpele test call
        client.get_athlete()
        return client
    except:
        # Token verlopen, ververs het
        print("Token verlopen, vernieuwen...")
        token_response = client.refresh_access_token(
            client_id = client_id,
            client_secret=client_secret,
            refresh_token=refresh_token
        )

        # Update .env met nieuwe tokens
        update_env_tokens(
            token_response['access_token'],
            token_response['refresh_token']
        )

        # Update client
        client.access_token = token_response['access_token']
        return client


def update_env_tokens(access_token, refresh_token):
    """Update .env bestand met nieuwe tokens"""
    env_path = os.path.join(os.path.dirname(__file__), '.env')

    with open(env_path, 'r') as file:
        lines = file.readlines()

    with open(env_path, 'w') as file:
        for line in lines:
            if line.startswith('STRAVA_ACCESS_TOKEN='):
                file.write(f'STRAVA_ACCESS_TOKEN={access_token}\n')
            elif line.startswith('STRAVA_REFRESH_TOKEN='):
                file.write(f'STRAVA_REFRESH_TOKEN={refresh_token}\n')
            else:
                file.write(line)

    # Reload environment
    load_dotenv(override=True)


# ============= TRAINING LOAD FUNCTIES =============

def calculate_training_loads(activities, days_atl=7, days_ctl=42):
    """
    Bereken ATL, CTL en TSB
    ATL (Acute Training Load) = korte termijn vermoeidheid (7 dagen)
    CTL (Chronic Training Load) = lange termijn fitness (42 dagen)
    TSB (Training Stress Balance) = CTL - ATL (form indicator)
    """
    now = datetime.now()

    # Verzamel Suffer Scores per dag
    daily_loads = {}

    for activity in activities:
        activity_date = activity.start_date_local.replace(tzinfo=None).date()
        days_ago = (now.date() - activity_date).days

        if days_ago > days_ctl:
            continue

        suffer_score = activity.suffer_score if activity.suffer_score else 0

        if activity_date not in daily_loads:
            daily_loads[activity_date] = 0
        daily_loads[activity_date] += suffer_score

    # Bereken ATL (laatste 7 dagen gemiddelde)
    atl_sum = 0
    atl_count = 0
    for i in range(days_atl):
        date = (now - timedelta(days=i)).date()
        if date in daily_loads:
            atl_sum += daily_loads[date]
            atl_count += 1

    atl = atl_sum / days_atl if days_atl > 0 else 0

    # Bereken CTL (laatste 42 dagen gemiddelde)
    ctl_sum = 0
    ctl_count = 0
    for i in range(days_ctl):
        date = (now - timedelta(days=i)).date()
        if date in daily_loads:
            ctl_sum += daily_loads[date]
            ctl_count += 1

    ctl = ctl_sum / days_ctl if days_ctl > 0 else 0

    # TSB = verschil tussen fitness en vermoeidheid
    tsb = ctl - atl

    return {
        "atl": round(atl, 1),
        "ctl": round(ctl, 1),
        "tsb": round(tsb, 1),
        "daily_loads": daily_loads
    }


def get_training_recommendation(tsb, atl, ctl):
    """
    Geef training advies op basis van TSB
    """
    if tsb < -30:
        status = "🔴 REST"
        advice = "Je bent zeer vermoeid. Neem minimaal 1-2 rustdagen. Je lichaam heeft herstel nodig."
        intensity = "Rust of zeer lichte recovery ride (<60% FTP)"
    elif tsb < -10:
        status = "🟡 EASY"
        advice = "Je bent licht vermoeid. Train licht of neem een rustdag. Geen intensieve workouts."
        intensity = "Zone 1-2 recovery rides, max 60-90 min"
    elif tsb < 5:
        status = "🟢 MODERATE"
        advice = "Goede balans! Je kunt normaal trainen met gematigde intensiteit."
        intensity = "Zone 2-3 endurance, tempo intervals mogelijk"
    elif tsb < 25:
        status = "🔵 HARD"
        advice = "Je bent fris en goed hersteld! Perfect voor intensieve training."
        intensity = "VO2max intervals, threshold work, race efforts"
    else:
        status = "⚪ DETRAINING RISK"
        advice = "Je hebt al lang niet intensief getraind. Verhoog je training load geleidelijk."
        intensity = "Bouw volume en intensiteit langzaam op"

    # Voeg context toe over fitness niveau
    fitness_context = ""
    if ctl < 30:
        fitness_context = "Je basis fitness is laag. Focus op volume opbouwen."
    elif ctl < 60:
        fitness_context = "Je hebt een solide basis fitness."
    else:
        fitness_context = "Je hebt een hoge fitness! Goed bezig."

    return {
        "status": status,
        "advice": advice,
        "intensity": intensity,
        "fitness_context": fitness_context
    }


def calculate_weekly_trends(daily_loads, weeks=8):
    """
    Bereken ATL en CTL per week voor trend analyse
    """
    now = datetime.now()
    weekly_trends = []

    for week_offset in range(weeks):
        week_start = now - timedelta(days=(week_offset + 1) * 7)
        week_end = now - timedelta(days=week_offset * 7)

        # ATL voor deze week (7 dagen gemiddelde)
        atl_sum = 0
        for i in range(7):
            date = (week_end - timedelta(days=i)).date()
            if date in daily_loads:
                atl_sum += daily_loads[date]
        atl = atl_sum / 7

        # CTL voor deze week (42 dagen gemiddelde tot die week)
        ctl_sum = 0
        for i in range(42):
            date = (week_end - timedelta(days=i)).date()
            if date in daily_loads:
                ctl_sum += daily_loads[date]
        ctl = ctl_sum / 42

        weekly_trends.append({
            "week_offset": week_offset,
            "week_label": f"Week -{week_offset}" if week_offset > 0 else "Deze week",
            "atl": round(atl, 1),
            "ctl": round(ctl, 1),
            "tsb": round(ctl - atl, 1)
        })

    return list(reversed(weekly_trends))  # Oudste eerst


def calculate_ramp_rate(weekly_trends):
    """
    Bereken ramp rate (% verandering in load week-over-week)
    Veilig: 5-10% per week
    Risico: >10% per week
    """
    if len(weekly_trends) < 2:
        return None

    # Vergelijk deze week met vorige week
    current_week = weekly_trends[-1]
    previous_week = weekly_trends[-2]

    if previous_week["atl"] == 0:
        return None

    ramp_rate = ((current_week["atl"] - previous_week["atl"]) / previous_week["atl"]) * 100

    # Bepaal status
    if ramp_rate > 15:
        status = "🔴 TE SNEL"
        warning = "WAARSCHUWING: Je load steeg >15% - hoog blessurerisico!"
    elif ramp_rate > 10:
        status = "🟡 SNEL"
        warning = "Let op: Load steeg >10% - monitor vermoeidheid nauwkeurig"
    elif ramp_rate > 5:
        status = "🟢 GOED"
        warning = "Gezonde progressie - load stijgt gecontroleerd"
    elif ramp_rate > -5:
        status = "🔵 STABIEL"
        warning = "Load is stabiel - goede maintenance"
    else:
        status = "⚪ DALEND"
        warning = "Load daalt - herstelperiode of detraining?"

    return {
        "rate": round(ramp_rate, 1),
        "status": status,
        "warning": warning,
        "current_atl": current_week["atl"],
        "previous_atl": previous_week["atl"]
    }


def generate_weekly_recommendation(tsb, atl, ctl, ramp_rate_data):
    """
    Genereer concrete weektraining plan
    """
    # Bereken target volume (uren deze week)
    current_weekly_hours = (atl * 7) / 60  # ATL is dagelijks, omzetten naar uren/week

    # Bepaal veilige volume aanpassing
    if ramp_rate_data and ramp_rate_data["rate"] > 10:
        # Te snel gestegen, afbouwen
        target_hours = current_weekly_hours * 0.9
        volume_advice = "⬇️ Verlaag volume met 10% (te snelle opbouw)"
    elif tsb < -30:
        # Zeer vermoeid
        target_hours = current_weekly_hours * 0.7
        volume_advice = "⬇️ Verlaag volume met 30% (herstel nodig)"
    elif tsb < -10:
        # Licht vermoeid
        target_hours = current_weekly_hours * 0.85
        volume_advice = "⬇️ Verlaag volume met 15% (recovery week)"
    elif tsb > 15:
        # Zeer fris, kan opbouwen
        target_hours = current_weekly_hours * 1.08
        volume_advice = "⬆️ Verhoog volume met 8% (goede vorm voor opbouw)"
    elif tsb > 5:
        # Fris
        target_hours = current_weekly_hours * 1.05
        volume_advice = "⬆️ Verhoog volume met 5% (veilige progressie)"
    else:
        # Stabiel
        target_hours = current_weekly_hours
        volume_advice = "➡️ Behoud huidig volume (goede balans)"

    # Bepaal workout mix
    if tsb < -30:
        # Herstel focus
        plan = {
            "endurance": 2,
            "recovery": 2,
            "intervals": 0,
            "rest": 3
        }
        intensity_note = "Focus op herstel - alleen zeer lichte ritten"
    elif tsb < -10:
        # Light week
        plan = {
            "endurance": 2,
            "recovery": 2,
            "intervals": 0,
            "rest": 3
        }
        intensity_note = "Recovery week - geen intensieve workouts"
    elif tsb < 5:
        # Moderate training
        plan = {
            "endurance": 3,
            "tempo": 1,
            "recovery": 1,
            "rest": 2
        }
        intensity_note = "Balanced week - endurance + 1x tempo"
    elif tsb < 15:
        # Build week
        plan = {
            "endurance": 2,
            "tempo": 1,
            "intervals": 1,
            "recovery": 1,
            "rest": 2
        }
        intensity_note = "Build week - endurance + intensiteit mogelijk"
    else:
        # Peak freshness - kan hard trainen
        plan = {
            "endurance": 2,
            "intervals": 2,
            "recovery": 1,
            "rest": 2
        }
        intensity_note = "High intensity week - je bent fris genoeg!"

    return {
        "target_hours": round(target_hours, 1),
        "current_hours": round(current_weekly_hours, 1),
        "volume_advice": volume_advice,
        "plan": plan,
        "intensity_note": intensity_note
    }

# Initialiseer client
client = get_authenticated_client()

# Maak MCP server
server = Server("strava-mcp")


@server.list_tools()
async def list_tools() -> list[Tool]:
    """Lijst van beschikbare Strava tools"""
    return [
        Tool(
            name="get_recent_activities",
            description="Haal recente Strava activiteiten op (standaard laatste 10)",
            inputSchema={
                "type": "object",
                "properties": {
                    "limit": {
                        "type": "number",
                        "description": "Aantal activiteiten (max 30)",
                        "default": 10
                    }
                }
            }
        ),
        Tool(
            name="get_activity_details",
            description="Krijg gedetailleerde info van een specifieke activiteit",
            inputSchema={
                "type": "object",
                "properties": {
                    "activity_id": {
                        "type": "string",
                        "description": "ID van de activiteit"
                    }
                },
                "required": ["activity_id"]
            }
        ),
        Tool(
            name="get_weekly_stats",
            description="Wekelijkse trainingsstatistieken (afstand, tijd, TSS/DTL)",
            inputSchema={
                "type": "object",
                "properties": {
                    "weeks": {
                        "type": "number",
                        "description": "Aantal weken terug (default: 4)",
                        "default": 4
                    }
                }
            }
        ),
        Tool(
            name="get_training_load_analysis",
            description="Analyseer training load met ATL, CTL, TSB en geef REST of TRAIN advies",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="get_weekly_training_plan",
            description="Krijg een concreet weekplan met aanbevolen uren, workout types en intensiteiten gebaseerd op je huidige status",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    """Voer tool uit"""

    if name == "get_recent_activities":
        limit = arguments.get("limit", 10)
        activities = client.get_activities(limit=limit)

        result = "🚴 RECENTE ACTIVITEITEN\n\n"
        for activity in activities:
            date = activity.start_date_local.strftime("%d-%m-%Y %H:%M")
            distance = round(float(activity.distance) / 1000, 1) if activity.distance else 0
            duration = str(activity.moving_time).split('.')[0]  # HH:MM:SS

            result += f"📅 {date}\n"
            result += f"   {activity.name}\n"
            result += f"   📏 {distance} km | ⏱️ {duration}\n"
            if activity.average_heartrate:
                result += f"   ❤️ {int(activity.average_heartrate)} bpm avg\n"
            result += f"   ID: {activity.id}\n\n"

        return [TextContent(type="text", text=result)]

    elif name == "get_activity_details":
        activity_id = arguments["activity_id"]
        activity = client.get_activity(activity_id)

        result = f"📊 ACTIVITEIT DETAILS\n\n"
        result += f"🏷️ Naam: {activity.name}\n"
        result += f"📅 Datum: {activity.start_date_local.strftime('%d-%m-%Y %H:%M')}\n"
        result += f"📏 Afstand: {round(float(activity.distance) / 1000, 1)} km\n"
        result += f"⏱️ Tijd: {activity.moving_time}\n"
        result += f"⚡ Avg Speed: {round(float(activity.average_speed) * 3.6, 1)} km/u\n"

        if activity.average_heartrate:
            result += f"❤️ Avg HR: {int(activity.average_heartrate)} bpm\n"
        if activity.max_heartrate:
            result += f"❤️ Max HR: {int(activity.max_heartrate)} bpm\n"
        if activity.average_watts:
            result += f"⚡ Avg Power: {int(activity.average_watts)}W\n"
        if activity.suffer_score:
            result += f"💪 Suffer Score: {activity.suffer_score}\n"

        result += f"\n📝 Beschrijving: {activity.description or 'Geen beschrijving'}\n"

        return [TextContent(type="text", text=result)]


    elif name == "get_weekly_stats":

        weeks = arguments.get("weeks", 4)

        activities = client.get_activities(limit=200)

        # Groepeer per week

        weekly_data = {}

        now = datetime.now()

        for activity in activities:

            activity_date = activity.start_date_local.replace(tzinfo=None)

            week_num = (now - activity_date).days // 7

            if week_num >= weeks:
                continue

            week_label = f"Week -{week_num}" if week_num > 0 else "Deze week"

            if week_label not in weekly_data:
                weekly_data[week_label] = {

                    "distance": 0,

                    "time": timedelta(),

                    "activities": 0

                }

            weekly_data[week_label]["distance"] += float(activity.distance) / 1000

            if activity.moving_time:
                weekly_data[week_label]["time"] += activity.moving_time

            weekly_data[week_label]["activities"] += 1

        result = f"📈 WEKELIJKSE STATISTIEKEN (laatste {weeks} weken)\n\n"

        for week in sorted(weekly_data.keys(), reverse=True):
            data = weekly_data[week]

            hours = data["time"].total_seconds() / 3600

            result += f"{week}:\n"

            result += f"  🚴 {data['activities']} ritten\n"

            result += f"  📏 {round(data['distance'], 1)} km\n"

            result += f"  ⏱️ {round(hours, 1)} uur\n\n"

        return [TextContent(type="text", text=result)]


    elif name == "get_training_load_analysis":

        activities = list(client.get_activities(limit=200))

        # Bereken training loads

        loads = calculate_training_loads(activities)

        recommendation = get_training_recommendation(

            loads["tsb"],

            loads["atl"],

            loads["ctl"]

        )

        # Bereken weekly trends

        weekly_trends = calculate_weekly_trends(loads["daily_loads"], weeks=8)

        # Bereken ramp rate

        ramp_rate = calculate_ramp_rate(weekly_trends)

        result = "🏋️ TRAINING LOAD ANALYSE\n\n"

        result += f"📊 HUIDIGE STATUS\n"

        result += f"ATL (Acute - 7 dagen): {loads['atl']}\n"

        result += f"CTL (Chronic - 42 dagen): {loads['ctl']}\n"

        result += f"TSB (Balance): {loads['tsb']}\n\n"

        # Ramp rate warning

        if ramp_rate:
            result += f"📈 RAMP RATE (week-over-week)\n"

            result += f"{ramp_rate['status']}: {ramp_rate['rate']:+.1f}%\n"

            result += f"Vorige week ATL: {ramp_rate['previous_atl']}\n"

            result += f"Deze week ATL: {ramp_rate['current_atl']}\n"

            result += f"⚠️ {ramp_rate['warning']}\n\n"

        result += f"🎯 ADVIES: {recommendation['status']}\n"

        result += f"{recommendation['advice']}\n\n"

        result += f"💪 Aanbevolen intensiteit:\n{recommendation['intensity']}\n\n"

        result += f"📈 Fitness context:\n{recommendation['fitness_context']}\n\n"

        # Weekly trends tabel

        result += f"📊 WEEKLY TRENDS (laatste 8 weken)\n"

        result += f"{'Week':<12} {'ATL':>6} {'CTL':>6} {'TSB':>6}\n"

        result += f"{'-' * 12} {'-' * 6} {'-' * 6} {'-' * 6}\n"

        for trend in weekly_trends[-8:]:  # Laatste 8 weken

            result += f"{trend['week_label']:<12} {trend['atl']:>6.1f} {trend['ctl']:>6.1f} {trend['tsb']:>6.1f}\n"

        return [TextContent(type="text", text=result)]

    elif name == "get_weekly_training_plan":
        activities = list(client.get_activities(limit=200))

    # Bereken huidige status
    loads = calculate_training_loads(activities)
    weekly_trends = calculate_weekly_trends(loads["daily_loads"], weeks=8)
    ramp_rate = calculate_ramp_rate(weekly_trends)

    # Genereer weekplan
    plan = generate_weekly_recommendation(
        loads["tsb"],
        loads["atl"],
        loads["ctl"],
        ramp_rate
    )

    result = "📋 WEEKTRAINING PLAN\n\n"
    result += f"⏱️ VOLUME ADVIES\n"
    result += f"Huidige week: ~{plan['current_hours']} uur\n"
    result += f"Aanbevolen: ~{plan['target_hours']} uur\n"
    result += f"{plan['volume_advice']}\n\n"

    result += f"🏋️ WORKOUT MIX\n"
    for workout_type, count in plan['plan'].items():
        emoji = {"endurance": "🚴", "tempo": "⚡", "intervals": "🔥",
                 "recovery": "💤", "rest": "🛋️"}.get(workout_type, "📝")
        result += f"{emoji} {workout_type.capitalize()}: {count}x\n"

    result += f"\n💡 {plan['intensity_note']}\n"

    return [TextContent(type="text", text=result)]

    return [TextContent(type="text", text=f"Onbekende tool: {name}")]


async def main():
    """Start MCP server"""
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options()
        )


if __name__ == "__main__":
    asyncio.run(main())