# somnia

somnia is an iPhone app for one person's night. It follows heart rate, movement, and heart-rate variability, keeps what stood out, and lets a caregiver see when an alarm is still waiting.

Krish Hariharan is the person in the app. somnia does not diagnose seizures or replace medical care. A wearable is not connected yet. The nights on the graphs are generated and labeled as synthetic, and they travel through the same service a watch would use later.

## Vultr

Vultr holds the night and writes the sentences.

Cloud Compute runs the Somnia service. The phone sends each window there. The service stores it, scores it, and decides whether it is quiet sleep, a turn, a heart-rate observation, or an alarm. Postgres keeps the nights, the events, and the log. The phone does not score on its own.

Serverless Inference writes the words from those saved measurements. It writes the summary in Insights and the "likely" line on each log entry. The phone never calls the model. The model does not produce the anomaly score, and it does not decide the alarm. If it cannot answer, the service keeps a fixed sentence and says so on the card.

## During the night

Each window records heart rate, how far that rate sits from a resting baseline of 62 bpm, motion, and beat-to-beat variability (RMSSD, in milliseconds).

An Isolation Forest scores how unusual the window is from heart rate and motion. A higher score means more unusual. The score is not a probability of a seizure. Variability is drawn on the home graph and printed on the log. It is not one of the score's inputs.

A stretch of strong movement together with a heart rate at least 20% above that baseline opens an alarm. A raised heart rate without that movement is saved as an observation. Movement in the range of a turn in bed is logged and does not open an alarm. Quiet sleep stays on the graph and is left out of the log.

## On the phone

**Home** shows whether monitoring is on, the latest heart rate and motion, movement through the night, and variability through the night. The longer notes under the graphs open from Read more. Reset clears the graphs, the alarms, and the log on the service. Attach wearable says import is not connected.

**Alarm** fills the screen for a possible seizure-like pattern. Sound and haptics play while that screen is open. I'm okay records that the person is safe. It does not decide whether the pattern was a seizure. Until then, the caregiver screen shows the alarm as still waiting. The app does not place a call or send a push notification, and the sound does not continue on a locked phone.

**Insights** opens from the headers Today, This week, Usual hour, Written summary, and Plan for Krish. The summary is the sentence Vultr wrote from the saved nights.

**Log** has one entry for each anomaly. The line says what it is likely — a seizure-like pattern, a heart-rate change, or a turn — and the card shows the heart rate, variability, and motion behind it.

**Profile** shows the sleep window and the wearable state. The person can leave a note on an event. The note is saved with the event for a later look. It does not change the score. From here the phone can open the caregiver screen.

**Caregiver** shows whether an alarm is still waiting and lists recent anomalies.

## Run it

```sh
make test
make serve
make ios
```

`make serve` listens on `http://127.0.0.1:8090`. Open `Somnia.xcodeproj`, choose the Somnia scheme, and run it on an iPhone simulator.

On Vultr Cloud Compute, the service starts with `docker compose -f infra/docker-compose.yml up --build -d` from `infra`. The phone's `SomniaAPIBaseURL` points at that host. The inference key stays in the service environment. The phone never sees it.
