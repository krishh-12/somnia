# Somnia

iPhone prototype for a hackathon demo. One synthetic patient, Krish Hariharan. The phone calls a Python service that scores heart-rate and motion with an Isolation Forest. That service is what runs on Vultr.

This version is the first usable section.

## What works now

- Demo entry as Patient, Caregiver, or Physician. No signup.
- Patient buttons run synthetic tests through the server.
- The seizure-like test saves an alarm. Quiet sleep does not.
- A heart-rate-only test saves an observation, not an alarm.
- Home shows the server’s heart rate, motion, and trend. Empty states stay empty.
- The on-screen alarm saves an acknowledgement. That acknowledgement is not a clinical label.
- History lists saved events. Insights shows the anomaly-score chart.
- Attach wearable opens an honest “not connected” sheet.

## Not in this version

Escalation to a caregiver and emergency contact, physician review, and the personal plan. Those use the events this section already saves.

## Run it

```sh
make test
make serve
make ios
```

`make serve` listens on `http://127.0.0.1:8090`. The iPhone simulator uses that address. Open `Somnia.xcodeproj`, choose the Somnia scheme, and run it on an iPhone simulator.

On a Vultr Cloud Compute VM, run `docker compose -f infra/docker-compose.yml up --build -d` and point `SomniaAPIBaseURL` at that host. No Vultr VM is provisioned from this machine yet.

Somnia does not diagnose seizures or replace medical care.
