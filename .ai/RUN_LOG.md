# RUN LOG

> 重要：日記ではなく「後から追える実行ログ」
> 各 Tick で Manager が更新する。

---

## Log Format

```yaml
- Tick: N
  Time: YYYY-MM-DD HH:MM
  Stage: KICKOFF | REQUIREMENTS | DESIGN | IMPLEMENTATION | INTEGRATION | RELEASE
  Actions:
    - action 1
    - action 2
  Commands:
    - /org-start
    - /org-tick
  Outputs:
    - summary of outputs
  Changed files:
    - .ai/FILE.md
  Notes:
    - any notes
```

---

## Logs

(初期状態 - /org-start 実行後に記録開始)
