# Jupiter Vacuum

A custom Flutter controller app for my Tuya / SmartLife robot vacuum.

## Why this exists

I like clean rooms. Maybe a little too much.

The robot vacuum already has an official app, and technically, it works. But the UI feels more like operating a printer from 2009 than controlling a tiny cleaning robot. I wanted something more fun, more direct, and more satisfying — basically a game-controller-style remote for my vacuum.

So this app exists because:

- I am a clean freak.
- Cleaning my room remotely is weirdly satisfying.
- The existing app UI sucks.
- A robot vacuum deserves a controller that feels less boring.
- Sometimes you just want to drive a dust-eating hockey puck around your room like it is a tiny obedient spaceship.

## What it does

Jupiter Vacuum lets me control my robot vacuum using a custom landscape Flutter UI.

Current features:

- Start cleaning
- Stop cleaning
- Send robot back to dock
- Change cleaning modes
- Control direction using a large joystick
- Send commands through Tuya Cloud
- Works remotely over the internet

## How it works

The app talks directly to the Tuya Cloud API.

```txt
Flutter App → Tuya Cloud API → Robot Vacuum
```

This project is currently made for personal use. The Tuya access secret is passed through environment files during build/run time and is not committed to GitHub.

Important note: putting secrets into a mobile app is not secure for public production apps. This is fine for a personal/private controller, but a public app should use a backend.

## Tuya Developer setup

This app needs Tuya Cloud credentials so it can send commands to the robot vacuum over the internet.

### 1. Create a Tuya Developer account

Go to the Tuya Developer Platform and create an account.

After signing in, open:

```txt
Cloud → Development
```

### 2. Create a Cloud project

Create a new cloud project.

Use settings similar to:

```txt
Project Name: Jupiter Vacuum
Industry: Smart Home
Development Method: Custom Development
Data Center: same region as your SmartLife account
```

The data center matters. If your SmartLife account/device is linked to the India region, use the India data center. If it is linked to another region, use that matching region.

### 3. Enable required APIs

In the project, open the API/service section and make sure the required APIs are enabled.

Useful services include:

```txt
IoT Core
Authorization
Smart Home Basic Service
Device Control
```

Names may vary slightly in Tuya's dashboard, but the important one for this app is the device control / IoT Core API.

### 4. Link your SmartLife account

Inside your Tuya cloud project, go to:

```txt
Devices → Link Tuya App Account
```

Then choose the Smart Life app option.

Tuya will show a QR code.

On your phone, open SmartLife and scan it:

```txt
SmartLife → Me/Profile → Scan
```

After linking, your robot vacuum should appear in the Tuya project device list.

### 5. Get the Device ID

After linking SmartLife, go to:

```txt
Devices → Manage Devices
```

Find your robot vacuum and copy its Device ID.

Add it to:

```txt
env/dev.json
```

as:

```json
"TUYA_DEVICE_ID": "your_tuya_device_id"
```

### 6. Get Access ID and Access Secret

Open your Tuya cloud project overview.

Copy:

```txt
Access ID / Client ID
Access Secret / Client Secret
```

Add them to:

```txt
env/dev.json
```

as:

```json
"TUYA_CLIENT_ID": "your_tuya_access_id",
"TUYA_CLIENT_SECRET": "your_tuya_access_secret"
```

Do not commit these values to GitHub.

### 7. Choose the correct Tuya endpoint

The endpoint depends on your Tuya data center.

For India, this project uses:

```txt
https://openapi.tuyain.com
```

Put it in:

```json
"TUYA_ENDPOINT": "https://openapi.tuyain.com"
```

If your Tuya project uses another region, use that region's Tuya OpenAPI endpoint.

### 8. Test the robot commands in Tuya API Explorer

Before running the app, test commands inside Tuya's API Explorer.

Open:

```txt
IoT Core → API List → Device Control(Standard Instruction Set)
```

Use:

```txt
Get the instruction set of the device
GET /v1.0/iot-03/devices/{device_id}/functions
```

This should show command codes like:

```txt
power_go
mode
direction_control
suction
```

Then test:

```txt
Send commands
POST /v1.0/iot-03/devices/{device_id}/commands
```

Example start command:

```json
{
  "commands": [
    {
      "code": "power_go",
      "value": true
    }
  ]
}
```

Example stop command:

```json
{
  "commands": [
    {
      "code": "power_go",
      "value": false
    }
  ]
}
```

Example dock command:

```json
{
  "commands": [
    {
      "code": "mode",
      "value": "chargego"
    }
  ]
}
```

Example direction command:

```json
{
  "commands": [
    {
      "code": "direction_control",
      "value": "forward"
    }
  ]
}
```

Example stop movement command:

```json
{
  "commands": [
    {
      "code": "direction_control",
      "value": "stop"
    }
  ]
}
```

If these work in Tuya API Explorer, the app should be able to control the robot too.

## Setup for development

### 1. Clone the repo

```bash
git clone <your-repo-url>
cd jupiter_vacuum
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Create your env file

Copy the example file:

```bash
cp env/example.json env/dev.json
```

Then edit:

```txt
env/dev.json
```

Add your real Tuya values:

```json
{
  "TUYA_CLIENT_ID": "your_tuya_access_id",
  "TUYA_CLIENT_SECRET": "your_tuya_access_secret",
  "TUYA_DEVICE_ID": "your_tuya_device_id",
  "TUYA_ENDPOINT": "https://openapi.tuyain.com"
}
```

Use the correct Tuya endpoint for your data center.

For India, this project uses:

```txt
https://openapi.tuyain.com
```

## Run in normal debug mode

```bash
flutter run --dart-define-from-file=env/dev.json
```

## Run in release mode

### iOS

```bash
flutter run --release --dart-define-from-file=env/dev.json
```

### Android

```bash
flutter run --release --dart-define-from-file=env/dev.json
```

## Build release files

### Android APK

```bash
flutter build apk --release --dart-define-from-file=env/dev.json
```

### Android App Bundle

```bash
flutter build appbundle --release --dart-define-from-file=env/dev.json
```

### iOS release build

```bash
flutter build ios --release --dart-define-from-file=env/dev.json
```

## Environment files

This repo should include:

```txt
env/example.json
```

This repo should not include:

```txt
env/dev.json
```

`env/dev.json` contains private Tuya credentials and should never be committed.

## Recommended `.gitignore` entries

Make sure your `.gitignore` includes:

```gitignore
# Secrets
env/dev.json
env/*.local.json
```

## Security note

This app is Flutter-only and does not use a backend. That keeps the setup simple, but it also means the Tuya credentials are eventually present in the compiled app.

That is acceptable for personal use, but not recommended for a public app.

A more secure future version should use:

```txt
Flutter App → Private Backend / Cloud Function → Tuya Cloud API → Robot Vacuum
```

That way, the Tuya Access Secret stays on the server instead of inside the compiled mobile app.
