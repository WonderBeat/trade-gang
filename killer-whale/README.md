# Killer Whale

Killer Whale is a high-performance cryptocurrency data monitoring and alerting service written in Zig. It specializes in detecting real-time updates from exchanges like Binance and Upbit, then rapidly disseminating alerts to trigger immediate actions across the Trade Gang ecosystem.

## Key Features

- **Exchange Monitoring**: Continuously monitors cryptocurrency exchange announcements (e.g., new listings, delistings) for specific catalogs.
- **Rapid Alerting**: Uses MQTT to broadcast alerts to other services when updates are detected.
- **Coordinated Action**: Sends announcements to the Mothership for further processing and coordination.
- **Proxy Support**: Integrates with anonymizer services to rotate proxies for resilient data fetching.
- **Performance-Oriented**: Built with Zig for speed and efficiency, suitable for high-frequency monitoring tasks.
- **Containerized Deployment**: Includes Docker support for easy deployment and scaling.

## Core Components

- `src/main.zig`: Main application logic for Binance monitoring.
- `src/upbit.zig`: Application logic for Upbit monitoring (alternative build target).
- `build.zig`: Build configuration for the Zig application, including dependencies.
- `Dockerfile`: Defines the container image for the application.
- `run.sh`: Example script showing various ways to run the application with different configurations.

## How It Works

1. The service starts by connecting to an MQTT broker and subscribing to exchange-specific topics.
2. It periodically fetches data from exchange APIs using configurable parameters (catalog, TLD, etc.).
3. When a new announcement is detected, it sends an alert via MQTT to notify other services.
4. It also sends a detailed announcement to the Mothership for centralized processing.
5. The service can operate in active mode (direct API polling) or passive mode (listening for MQTT alerts from other instances).

## Configuration

The service is configured via environment variables:

- `CATALOG`: The exchange catalog ID to monitor (e.g., 161 for Binance delistings, 48 for listings).
- `TLD`: The top-level domain to use for API requests (e.g., "com", "info").
- `MOTHERSHIP`: Address of the Mothership service to send announcements to.
- `MQTT`: Address of the MQTT broker for alerting.
- `ANONYMIZER`: (Optional) Address of a proxy anonymizer service.
- `FETCH_URL`: (Optional) URL to fetch proxy lists from.
- `PASSIVE`: (Optional) If set, enables passive mode where the service only listens for MQTT alerts.

## Building and Running

### Prerequisites

- Zig compiler (version specified in `build.zig`)
- libcurl development libraries
- Docker (for containerized deployment)

### Local Build

```bash
zig build
```

### Docker Build

```bash
docker build -t killer-whale .
```

### Running

See `run.sh` for example commands. Adjust environment variables as needed for your deployment.
