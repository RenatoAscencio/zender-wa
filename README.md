# WhatsApp Server in Docker

A production-ready Docker image to deploy the Titansys WhatsApp service. This project provides a reliable and automated way to run the service, including auto-restart, persistent data management, and easy-to-use administration commands.

![GitHub Actions](https://github.com/RenatoAscencio/zender-wa/actions/workflows/docker-publish.yml/badge.svg)

---

## 📜 Official Script Information

This Docker image is designed to run the **Zender** script. To use this service, you must have a valid license.

-   **Title:** Zender - WhatsApp & SMS Gateway SaaS for Automation, Chatbots, and Marketing
-   **Purchase URL:** [https://codecanyon.net/item/zender-android-mobile-devices-as-sms-gateway-saas-platform/26594230](https://codecanyon.net/item/zender-android-mobile-devices-as-sms-gateway-saas-platform/26594230)
-   **Official Documentation:** [https://support.titansystems.ph/hc/articles/9/12/1/introduction](https://support.titansystems.ph/hc/articles/9/12/1/introduction)

---

## ✨ Key Features

-   **Robust Base:** Built on Ubuntu 22.04 for maximum compatibility.
-   **Auto-Restart:** Uses `cron` to monitor the service and automatically bring it up if it stops.
-   **Persistent Data:** Uses Docker volumes to ensure your session data (`/data/whatsapp-server`) is never lost.
-   **Multiple Deployment Modes:** Supports automated deployments via environment variables or a guided interactive setup.
-   **Management Commands:** Includes simple commands to install, configure, update, restart, and stop the service.

---

## 🚀 Deployment

There are three ways to deploy this container.

### Method 1: Easypanel Template (Easiest)

This is the simplest way to get started on Easypanel.

1.  Go to the template generator URL: **[https://general-templates.vrfg1p.easypanel.host/zender-wa](https://general-templates.vrfg1p.easypanel.host/zender-wa)**
2.  The page will generate a block of YAML code. Click the **Copy** button to copy this code.
3.  In your Easypanel project, click **+ Service**, go to the **Custom** tab, and select **Create From Schema**.
4.  **Paste the YAML code** you copied into the text box.
5.  Easypanel will pre-fill all the necessary settings. Just go to the **Environment** tab, enter your `PCODE` and `KEY`, and click **Deploy**.

### Method 2: Automated Deployment (via Environment Variables)

This method is ideal for platforms like Easypanel, CapRover, or Portainer.

1.  **Create the Service:** In your control panel, create a new service of type "App".
2.  **Select Image:** Choose the option to deploy from a Docker image and use:
    `renatoascencio/zender-wa:latest`
3.  **Configure Environment Variables:** Go to the **Environment** tab and add your keys.
    -   `PCODE`: `your-secret-pcode-here`
    -   `KEY`: `your-secret-key-here`
    -   `PORT`: `443` (Optional, defaults to 443)
4.  **Configure Volume:** Go to the **Volumes** tab and map a volume.
    -   **Container Path:** `/data/whatsapp-server`
5.  **Deploy:** The container will start, read your variables, and launch the service automatically.

### Method 3: Interactive Manual Deployment

Use this method on any generic server with Docker.

1.  **Start the Container:** Launch the container in standby mode.
    `docker run -d -p 443:443 --name zender-wa-app -v whatsapp_data:/data/whatsapp-server --restart always renatoascencio/zender-wa:latest`
2.  **Access the Console:** Get a terminal inside the container.
    `docker exec -it zender-wa-app bash`
3.  **Run the Installer:** Inside the console, run the installation command.
    `install-wa`
4.  The script will guide you to enter your keys, and the service will start.

---

## 🛠️ Management Commands

Access the container's console (`docker exec -it zender-wa-app bash`) to use these commands:

-   `install-wa`: Performs the initial setup (only in manual mode).
-   `config-wa`: Interactively edits the `.env` variables.
-   `update-wa`: Downloads the latest version of the binary.
-   `restart-wa`: Restarts the WhatsApp service.
-   `stop-wa`: Stops the WhatsApp service.

---

## 💾 Data Persistence

The container is designed to be "ephemeral," but your data is persistent. Everything saved inside the `/data/whatsapp-server` folder (sessions, logs, etc.) is stored in a Docker volume, separate from the container's lifecycle. You can update, delete, and redeploy the container as many times as you want without losing your data.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## ✍️ Author & Credits

-   **Author:** [@RenatoAscencio](https://github.com/RenatoAscencio)
-   **Official Repository:** [https://github.com/RenatoAscencio/zender-wa](https://github.com/RenatoAscencio/zender-wa)
