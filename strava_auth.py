import os
import stat
import tempfile
from urllib.parse import urlparse, parse_qs
from stravalib.client import Client
from dotenv import load_dotenv
import webbrowser

# Load environment variables
load_dotenv()


class StravaAuth:
    def __init__(self):
        self.client_id = os.getenv('STRAVA_CLIENT_ID')
        self.client_secret = os.getenv('STRAVA_CLIENT_SECRET')
        self.client = Client()

    def authorize(self):
        """Start OAuth flow — opens browser for authorization"""
        authorize_url = self.client.authorization_url(
            client_id=self.client_id,
            redirect_uri='http://localhost:8000/authorized',
            scope=['read', 'activity:read_all']
        )

        print(f"\n🔑 Open this URL in your browser:")
        print(authorize_url)
        print("\nAfter authorization you'll get a URL with 'code=...'")
        print("Copy the full URL and paste it here:\n")

        # Open browser automatically
        webbrowser.open(authorize_url)

        # Wait for user input
        redirect_response = input("Paste the redirect URL: ")

        # Extract code from URL
        parsed = urlparse(redirect_response.strip())
        params = parse_qs(parsed.query)
        if 'code' not in params:
            print("\n❌ No authorization code found in the URL.")
            print("Make sure you paste the complete redirect URL.")
            return None

        code = params['code'][0]

        # Exchange code for tokens
        token_response = self.client.exchange_code_for_token(
            client_id=self.client_id,
            client_secret=self.client_secret,
            code=code
        )

        # Update .env file
        self._update_env_tokens(
            token_response['access_token'],
            token_response['refresh_token']
        )

        print("\n✅ Authentication successful! Tokens saved to .env")
        return token_response

    def _update_env_tokens(self, access_token, refresh_token):
        """Update .env file with new tokens (atomic write)"""
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


if __name__ == "__main__":
    auth = StravaAuth()
    auth.authorize()
