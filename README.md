# somnia

somnia scans a night of wearable data for seizure-like activity. It takes heart rate, movement, and heart-rate variability, the same kind of readings an Apple Watch records, raises an alarm while the night is still happening, and keeps the nights as a neurological profile a physician can use.

A caregiver can see an alarm that is still waiting, read a plan for that night, and ask a question about it. Vultr stores the night, compiles the lines the scan uses, and writes the sentences.

## Vultr

Vultr is the center of the night.

Cloud Compute runs the Somnia service. The phone sends each window there. The service stores it in Postgres, scores how unusual it is, and decides whether it is quiet sleep, a turn, a heart-rate change, or an alarm.

Serverless Inference compiles the published ranges for nocturnal seizures into the three lines the night is compared against: a motion line, a heart-rate line, and a variability line. Those lines are drawn on the graphs and used by the alarm. Inference then writes the night in words. It writes the Insights summary, the likely line on each log entry, the sentence on the caregiver plan, and the answer when a caregiver asks about the night. The phone talks only to the Somnia service.

## During the night

Each window records heart rate, how far that rate sits from a resting baseline of 62 bpm, motion, and beat-to-beat variability (RMSSD, in milliseconds).

An Isolation Forest scores how unusual the window is from heart rate and motion. A higher score means more unusual. Variability is drawn on the home graph and printed on the log, next to that score.

The compiled lines separate the night. Strong movement that continues, together with a heart rate over the compiled line, opens an alarm. A heart-rate rise without that movement is saved as an observation. Movement in the range of a turn in bed is logged and leaves the alarm closed. Quiet sleep stays on the graph and stays out of the log. The heart-rate line sits inside the published rise of about 20–70% from rest.

## On the phone

**Home** shows whether monitoring is on, the latest heart rate and motion, movement through the night, and variability through the night. Dashed lines are the lines Vultr compiled. Red points are the seizure-like pattern. The longer notes under the graphs open from Read more. Run anomaly adds the next stretch of the night. Reset clears the graphs, the alarms, and the log together. Attach wearable is where a watch joins this same night.

**Alarm** fills the screen for a seizure-like pattern. Sound and haptics play while that screen is open. I'm okay records that the person is safe, and the night stays in the profile. The phone then asks what was happening: turning over, awake, or not sure, with an optional note saved on the event. While the alarm is still waiting, the caregiver screen shows it.

**Insights** opens from the headers Today, This week, Usual hour, Written summary, and Plan for Krish. The summary and the plan come from the saved night. Vultr writes the summary.

**Log** has one entry for each anomaly. Vultr writes the likely line: a seizure-like pattern, a heart-rate change, or a turn. The card shows the heart rate, variability, and motion behind it.

**Profile** shows the name, the role, and the sleep window. From here the phone opens the caregiver screens.

**Caregiver, Home** shows whether an alarm is still waiting and lists recent anomalies with the likely line Vultr wrote for each one.

**Caregiver, Plan** holds the rest of that night. Vultr writes a sentence for the person nearby. Under it is the plan: the summary, the action, and the usual hour. Share this night sends the brief, the plan, and the recent log lines. Ask about this night takes a question, and Vultr answers from the saved night, the log, the notes, and the plan.

## Run it

```sh
make test
make serve
make ios
```

`make serve` listens on `http://127.0.0.1:8090`. Open `Somnia.xcodeproj`, choose the Somnia scheme, and run it on an iPhone.

On Vultr Cloud Compute, the service starts with `docker compose -f infra/docker-compose.yml up --build -d` from `infra`. The phone's `SomniaAPIBaseURL` points at that host. The inference key stays in the service environment.
