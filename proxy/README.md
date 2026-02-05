# Feed Proxy for Blocked Feeds

Some feed sources (Daring Fireball, Kottke, etc.) block datacenter IPs. This proxy routes those requests through [ScraperAPI](https://www.scraperapi.com/) which uses residential IPs.

## Setup

1. **Get a ScraperAPI key** – [Sign up](https://www.scraperapi.com/signup) for 1,000 free credits/month.

2. **Deploy the proxy** (choose one):

   **Fly.io (recommended, free tier):**
   ```bash
   cd proxy
   fly launch   # creates app, answer prompts
   fly secrets set SCRAPERAPI_KEY=your_api_key
   fly deploy
   ```
   Note the app URL (e.g. `https://feedbin-feed-proxy.fly.dev`).

   **Heroku (second app):**
   ```bash
   cd proxy
   git init && git add . && git commit -m "Proxy"
   heroku create your-feedbin-proxy
   heroku config:set SCRAPERAPI_KEY=your_api_key -a your-feedbin-proxy
   git push heroku main
   ```

3. **Configure the main Feedbin app:**
   ```bash
   heroku config:set \
     FEEDKIT_PROXY_HOST="https://feedbin-feed-proxy.fly.dev" \
     FEEDKIT_PROXIED_HOSTS="daringfireball.net,feeds.kottke.org" \
     -a calm-journey-58657
   ```

   Add more hosts to `FEEDKIT_PROXIED_HOSTS` (comma-separated) as you discover blocked feeds.

4. **Re-run the import:**
   ```bash
   heroku run rails feeds:import_from_export -a calm-journey-58657
   ```

## How it works

- Feedkit sends requests for proxied hosts to this service with `X-Proxy-Host` set.
- This proxy forwards the request to ScraperAPI, which fetches from residential IPs.
- ScraperAPI returns the feed content; the proxy passes it back to Feedkit.

## Cost

- ScraperAPI: 1,000 free credits/month. Each feed refresh = 1 credit. ~2 feeds × 96/day ≈ 6,000/month, so free tier covers light use; upgrade for more.
- Fly.io: Free tier includes 3 shared VMs, enough for this proxy.
