# aaPanel on Coolify

This repository builds a Docker image that runs [aaPanel](https://github.com/aaPanel/aaPanel) as a Coolify application. The image uses Ubuntu 22.04, installs the current English panel with the [official installer](https://www.aapanel.com/script/install_panel_en.sh) during the image build, and starts the panel without systemd.

The panel listens on port **8888** inside the container. Coolify's proxy publishes your domain on ports 80 and 443 and forwards traffic to that internal port. Panel files, websites, and databases live in **`/www`**, which must be a persistent volume.

## Requirements

- A Coolify server whose proxy can use host ports 80 and 443.
- A DNS record that points the panel domain to that server.
- Outbound internet from the server while the image builds. The build downloads packages from Ubuntu and aaPanel.
- Enough disk for an image of about 1.8 GB. The image contains the panel and its Python environment.
- At least 2 GB of memory for the application before you install Nginx, MySQL, or PHP from the panel. The panel process itself needs about 1 GB.

## Deploy on Coolify

Create the resource before the first deployment and attach the volume first. The first boot writes the panel login into `/www`. A volume added after that boot does not recover those files.

1. Open the project and environment, then select **+ New**.
2. Choose a public repository, or a private repository with a deploy key. Paste the repository URL and select **Check Repository**.
3. Select **Dockerfile** as the build pack.
4. Set **Base Directory** to `/`.
5. Set **Dockerfile Location** to `/Dockerfile`.
6. Open the application and set **Ports Exposes** to `8888`.
7. Leave **Ports Mappings** empty for the panel. A host mapping bypasses the Coolify proxy.
8. Add the domain `https://panel.example.com`, using your own hostname.
9. Add the environment variables below as runtime variables.
10. Open **Persistent Storage**, select **Add**, then **Volume Mount**. Set **Destination Path** to `/www`. Leave the source empty so Docker creates a named volume.
11. Leave **Custom Docker Options** empty. The image does not need `--privileged`.
12. Select **Deploy**.

The first build installs aaPanel and can take several minutes. After the container is healthy, open the runtime logs and use the security entrance printed there.

## Environment variables

Set the login values before the first deploy. aaPanel accepts letters, numbers, underscore, comma, and period in the username and password. The password also has to be 8 to 64 characters. `admin` and `root` are rejected as usernames. The security entrance has to start with `/` and then use 6 to 32 letters, numbers, underscore, or hyphen.

| Variable | Default | Applied | Purpose |
| --- | --- | --- | --- |
| `AAPANEL_PORT` | `8888` | Every start | Port inside the container. Keep it equal to **Ports Exposes**. |
| `AAPANEL_USERNAME` | Random | First start | Panel username. |
| `AAPANEL_PASSWORD` | Random | First start | Panel password. |
| `AAPANEL_ENTRY` | Random path | First start | Security entrance, for example `/panelentry`. |
| `AAPANEL_SSL` | `off` | First start | `off` keeps the panel on HTTP so Coolify can terminate TLS. |
| `TZ` | `UTC` | Every start | Container timezone, for example `America/Sao_Paulo`. |

Example:

```text
AAPANEL_PORT=8888
AAPANEL_USERNAME=paneladmin
AAPANEL_PASSWORD=PanelPass123
AAPANEL_ENTRY=/panelentry
AAPANEL_SSL=off
TZ=UTC
```

With those values the panel URL is:

```text
https://panel.example.com/panelentry
```

The site root does not show the login form. aaPanel answers there with its hidden-entrance page. That response still means the container is up.

`AAPANEL_USERNAME`, `AAPANEL_PASSWORD`, `AAPANEL_ENTRY`, and `AAPANEL_SSL` are stored on the volume during the first successful start. Later changes to those variables are ignored until the initial login is recreated:

```bash
rm -f /www/.aapanel-initialized /www/.aapanel-credentials-printed
```

Restart the container after removing those files. Websites and databases under `/www` stay in place. `AAPANEL_PORT` is applied on every start.

## Open the panel

1. Confirm the DNS record points at the Coolify server.
2. Wait until the deployment is healthy.
3. Read the runtime logs. The first start prints the entrance, username, and password.
4. Open `https://<your-domain><entrance>`.

The same login is stored in the volume at `/www/.aapanel-credentials`. From the Coolify terminal you can also run:

```bash
bt default
```

Change the password in the panel after the first login.

## HTTPS

Leave `AAPANEL_SSL=off`. Coolify's proxy requests the certificate for the domain and talks HTTP to port 8888 inside the container. Turning the panel's own SSL on makes the proxy send plain HTTP to an HTTPS port, and the domain stops opening.

## Ports and websites

| Container port | Used by | Coolify setting |
| --- | --- | --- |
| `8888` | Panel | **Ports Exposes**: `8888` |
| `80` | Websites created in aaPanel | Optional **Ports Mappings** entry such as `8080:80` |
| `443` | HTTPS websites created in aaPanel | Optional **Ports Mappings** entry such as `8443:443` |
| `888` | phpMyAdmin, after you install it | Optional mapping such as `8888` is already the panel; use a free host port, for example `8880:888` |
| `3306` | MySQL, after you install it | Optional mapping such as `3306:3306` |
| `21` and `39000-40000` | FTP, after you install it | Optional mappings |

Coolify's proxy already owns host ports 80 and 443. Leave the container ports 80 and 443 unpublished when sites should be separate Coolify applications. To reach a site served by the web server installed inside this container, add a **Ports Mappings** entry on a free host port. A site mapped as `8080:80` is available at `http://<server>:8080`. A host port mapping also turns off rolling updates for this application.

Open the matching port in the server firewall or security group when you publish one.

## Persistent data

Everything aaPanel needs to keep is under `/www`:

- `/www/server/panel` is the panel.
- `/www/wwwroot` is website files.
- `/www/server/data` is MySQL data after MySQL is installed.
- `/www/server/panel/vhost` is web-server site configuration.
- `/www/wwwlogs` is site logs.
- `/www/backup` is panel backups.

Back up that volume outside the container. Replacing the container keeps the data only when the same volume is mounted at `/www`.

## Updates

Use aaPanel's update button inside the panel to upgrade an existing installation. A new image build installs the current panel into the image seed. A volume that already contains `/www/server/panel` keeps the installed copy and is not overwritten.

Deleting the volume and deploying again creates a new panel and removes the sites and databases stored there.

## Run the image locally

```bash
docker build -t aapanel-coolify .
docker volume create aapanel-www
docker run -d --name aapanel \
  --init \
  -p 8888:8888 \
  -e AAPANEL_USERNAME=paneladmin \
  -e AAPANEL_PASSWORD=PanelPass123 \
  -e AAPANEL_ENTRY=/panelentry \
  -e AAPANEL_SSL=off \
  -v aapanel-www:/www \
  aapanel-coolify
```

Open `http://127.0.0.1:8888/panelentry`.

## Troubleshooting

**The domain opens and shows a not-found page.** Add the security entrance from the runtime logs or from `/www/.aapanel-credentials`. A request without a browser user agent, such as a plain `curl`, receives that same page even on the correct entrance. Open the entrance in a browser.

**Coolify shows Bad Gateway or No available server.** Set **Ports Exposes** to `8888`, remove a host mapping for `8888`, and confirm the container health check is passing. The process listens on `0.0.0.0` inside the container.

**The health check fails immediately.** The image includes its own check. Leave the Coolify HTTP health check disabled, because a check that requires HTTP 200 on `/` fails when aaPanel hides that path. The image treats a completed response from port 8888 as healthy.

**The first deployment stays on the build for a long time.** The Dockerfile runs the official installer. The runtime log starts only after that build finishes.

**The login from the build log does not work.** The image replaces the installer password before the container serves traffic. Use the runtime log or `/www/.aapanel-credentials`.

**A website on port 80 or 443 inside the panel is not reachable on the normal domain.** The Coolify proxy is using those host ports. Publish a free host port in **Ports Mappings**, or deploy that site as its own Coolify application.
