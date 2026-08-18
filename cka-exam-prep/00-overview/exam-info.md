# Exam Mechanics & Logistics

## Format
- **Performance-based** — you SSH into live clusters and solve real tasks via terminal in a remote browser environment (PSI proctored).
- **No multiple choice.** Every task is graded by an automated checker that inspects cluster state.
- **~15–20 tasks** in 2 hours → ~6–8 minutes per task average. Some tasks are 2-minute one-liners; others are 15-minute multi-step scenarios. Budget accordingly.
- Each task lists a **point value** (e.g., "4%", "7%"). Sort by value if you're behind.
- Each task specifies a **context to switch to**: `kubectl config use-context <name>`. **Forget this and you grade against the wrong cluster.**

## Score & passing
- Passing score: **66%**
- Partial credit awarded — attempt every task even if you can only do the first step.
- Results emailed within **24 hours** of submission.

## Environment
- Single browser tab — proctor sees your screen and webcam continuously.
- One terminal window with tabs/panes (tmux is pre-installed). Right side has the task panel.
- Pre-installed: `kubectl`, `helm`, `kustomize`, `jq`, `yq`, `vim`, `tmux`, `crictl`.
- `alias k=kubectl` and `complete -F __start_kubectl k` are **set by default** — verify on the first task.
- Allowed reference URLs (open second tab — proctor permits this):
  - `https://kubernetes.io/docs/` (and language subdomains)
  - `https://kubernetes.io/blog/`
  - `https://helm.sh/docs/`
  - The exam-specific tabs the UI provides

## Before exam day
- **ID** — passport / national ID with name matching the registration exactly
- **Webcam** — must rotate around the room
- **Workspace** — clear desk, no extra monitors, no phones, no headphones (unless approved)
- **Browser** — PSI Bridge / latest Chrome
- **Network** — wired if possible; ≥ 5 Mbps stable

## Day-of rules (the ones that catch people)
- Single monitor only. Disconnect external displays.
- No mug, no water bottle with a label, nothing on the desk except keyboard, mouse, ID.
- You can drink **clear water in a clear glass** — that's the only exception.
- You can take **bathroom breaks**, but the timer keeps running.
- No reading questions aloud, no muttering, no looking off-screen for too long.

## Retake policy
- Each exam purchase includes **one free retake** if you fail on the first attempt.
- You have **12 months** from purchase to schedule.
- If you no-show the first attempt, the retake voucher is forfeited.

## Killer.sh simulator
- **Two free 36-hour sessions** included with every CKA purchase.
- Harder than the real exam. If you score 70%+ on killer.sh, the real exam will feel easier.
- **Don't burn both sessions early.** Use the first ~2 weeks before exam, the second the day before.
- After the session ends, the questions + official solutions stay readable forever.
