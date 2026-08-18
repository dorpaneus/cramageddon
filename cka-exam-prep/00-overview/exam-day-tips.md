# Exam Day Strategy

## The 5-minute startup ritual (do this BEFORE touching task 1)

```bash
# 1. Confirm the k alias works (it should be pre-set; verify)
alias k=kubectl
k version --short

# 2. Add fast aliases for what you'll repeat 100x
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kaf='kubectl apply -f'
alias kdr='kubectl --dry-run=client -o yaml'

# 3. The two flags that save the most time
export do='--dry-run=client -o yaml'   # template generator
export now='--grace-period=0 --force'   # instant pod delete

# Usage:
# k run nginx --image=nginx $do > pod.yaml
# k delete pod stuck-pod $now

# 4. Enable autocomplete (verify it's already on)
source <(kubectl completion bash)
complete -F __start_kubectl k

# 5. vim setup — paste this in ~/.vimrc
cat <<'EOF' >> ~/.vimrc
set ts=2 sts=2 sw=2 expandtab
set number
set cursorline
EOF
```

## How to read a task

Each task has three parts:
1. **Setup** — what context to use, what cluster looks like
2. **Action** — what you must change/create
3. **Verify** — usually a kubectl command the grader will run

**Read all 3 parts before typing anything.** 30 seconds of reading saves 5 minutes of redo.

## Time management

| Time elapsed | Where you should be |
| --- | --- |
| 0:05 | Aliases set, first task picked |
| 0:30 | 4–5 easy tasks done |
| 1:00 | ~50% of points captured |
| 1:30 | All low-hanging fruit + 1 hard task |
| 1:45 | Last 15 min = re-check flagged + verify context switches |

**The flag button is your best friend.** Flag any task you spend >7 min on and move on.

## The "stuck for 3 minutes" rule

If you've been on a task for 3 minutes without making progress:
1. Re-read the task statement. (50% of the time it's a misread.)
2. Check `kubectl config current-context` — are you on the right cluster?
3. Check namespace — most tasks specify one. Use `-n <ns>` or `kubectl config set-context --current --namespace=<ns>`.
4. Flag and skip. Come back later.

## Common time sinks (avoid these traps)

- **Wrong namespace.** Every task says "in the namespace X" — miss it, lose all points.
- **Wrong context.** You did the work, but on the wrong cluster.
- **Hand-typing YAML.** Always start from `--dry-run=client -o yaml` or copy from kubernetes.io docs.
- **Manual etcd backup typo.** Practice the exact command. Single missed flag = 0 points.
- **Editing static pod manifests on wrong node.** `kube-apiserver.yaml` etc. live on the **control plane node**, not where you ssh'd in by default. Read the task.
- **Forgetting to apply after edit.** Static pods auto-reload from `/etc/kubernetes/manifests/`. Other things need `kubectl apply -f`.
- **Quoting in shell.** Don't use fancy quotes copied from PDFs. Re-type or paste plain.

## The right order to tackle tasks

1. **First pass** — solve everything that takes ≤ 3 minutes.
2. **Second pass** — medium tasks (3–7 minutes).
3. **Third pass** — the long troubleshooting/cluster-upgrade tasks.

**Why**: low-effort tasks have the same weight per minute as hard ones. Cluster upgrade is worth ~7% and takes ~15 min. A 1-min "create a Service" task might be worth 4%. Same points, much faster.

## Verifying your answers

After each task:
```bash
# Did the object actually get created in the right namespace?
k get <resource> -n <namespace>

# Is it healthy?
k get pods -n <ns> -o wide

# Does the grader's test command return what they expect?
# (run the exact one in the task description)
```

## What NOT to do

- Don't try to be clever. Use what the docs show.
- Don't `imperatively create a Deployment` and then immediately `edit` it 4 times. Generate YAML, edit once, apply.
- Don't run `kubectl delete --all` ever. Specify the resource.
- Don't `rm -rf` anything in `/etc/kubernetes/`.
- Don't `systemctl restart kubelet` unless the task asks you to. It can break things mid-exam.

## The 30-second pre-submit check

Before clicking "End Exam":
- [ ] All flagged questions revisited
- [ ] Every task: ran `kubectl get` on the resource you created/modified
- [ ] No leftover `vim` session blocking save
- [ ] Glanced at terminal for any red error messages you missed
