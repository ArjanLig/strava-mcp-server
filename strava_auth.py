import os
import stat
import tempfile
from urllib.parse import urlparse, parse_qs
from stravalib.client import Client
from dotenv import load_dotenv
import webbrowser

# Laad environment variables
load_dotenv()


class StravaAuth:
    def __init__(self):
        self.client_id = os.getenv('STRAVA_CLIENT_ID')
        self.client_secret = os.getenv('STRAVA_CLIENT_SECRET')
        self.client = Client()

    def authorize(self):
        """Start OAuth flow - opent browser voor autorisatie"""
        authorize_url = self.client.authorization_url(
            client_id=self.client_id,
            redirect_uri='http://localhost:8000/authorized',
            scope=['read', 'activity:read_all']
        )

        print(f"\n🔑 Open deze URL in je browser:")
        print(authorize_url)
        print("\nNa autorisatie krijg je een URL met 'code=...'")
        print("Kopieer de hele URL en plak hier:\n")

        # Open automatisch de browser
        webbrowser.open(authorize_url)

        # Wacht op user input
        redirect_response = input("Plak de redirect URL: ")

        # Haal code uit URL met veilige parsing
        parsed = urlparse(redirect_response.strip())
        params = parse_qs(parsed.query)
        if 'code' not in params:
            print("\n❌ Geen autorisatie code gevonden in de URL.")
            print("Zorg dat je de volledige redirect URL plakt.")
            return None

        code = params['code'][0]

        # Wissel code voor tokens
        token_response = self.client.exchange_code_for_token(
            client_id=self.client_id,
            client_secret=self.client_secret,
            code=code
        )

        # Update .env bestand
        self._update_env_tokens(
            token_response['access_token'],
            token_response['refresh_token']
        )

        print("\n✅ Authenticatie gelukt! Tokens opgeslagen in .env")
        return token_response

    def _update_env_tokens(self, access_token, refresh_token):
        """Update .env bestand met nieuwe tokens (atomic write)"""
        env_path = os.path.join(os.path.dirname(__file__), '.env')

        with open(env_path, 'r') as file:
            lines = file.readlines()

        fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(env_path))
        try:
            with os.fdopen(fd, 'w') as tmp_file:
                for line in lines:
                    if line.startswith('STRAVA_ACCESS_TOKEN='):
                        tmp_file.write(f'STRAVA_ACCESS_TOKEN={access_token}\n')
                    elif line.startswith('STRAVA_REFRESH_TOKEN='):
                        tmp_file.write(f'STRAVA_REFRESH_TOKEN={refresh_token}\n')
                    else:
                        tmp_file.write(line)
            os.chmod(tmp_path, stat.S_IRUSR | stat.S_IWUSR)
            os.replace(tmp_path, env_path)
        except Exception:
            os.unlink(tmp_path)
            raise


# Test functie
if __name__ == "__main__":
    auth = StravaAuth()
    auth.authorize()
