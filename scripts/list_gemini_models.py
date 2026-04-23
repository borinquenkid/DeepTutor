
import asyncio
import httpx
from deeptutor.services.config.env_store import get_env_store

async def list_gemini_models():
    env = get_env_store().load()
    api_key = env.get("GEMINI_API_KEY") or env.get("LLM_API_KEY")
    
    if not api_key:
        print("❌ No key found")
        return

    # Try both v1 and v1beta to see what we can find
    for version in ["v1", "v1beta"]:
        url = f"https://generativelanguage.googleapis.com/{version}/models"
        params = {"key": api_key}
        
        print(f"--- Checking {version} ---")
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, params=params)
                if response.status_code == 200:
                    data = response.json()
                    models = data.get("models", [])
                    print(f"Found {len(models)} total models in {version}:")
                    for m in models:
                        name = m["name"]
                        methods = ", ".join(m.get("supportedGenerationMethods", []))
                        print(f"  - {name} ({methods})")
                else:
                    print(f"❌ Failed {version}: {response.status_code} - {response.text}")
            except Exception as e:
                print(f"❌ Error checking {version}: {e}")

if __name__ == "__main__":
    asyncio.run(list_gemini_models())
