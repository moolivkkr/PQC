# websrv checkpoint (2026-11-14) - PARTIAL (budget warning at 100 tool calls)
DONE
- Web servers and proxies tab (f7dff530-a0a0 / body 10112461-0b3c): fully rewritten in the doc, all 8 sections + 2-part Full configuration files; old placeholder deleted. Doc rev 13.
- Tests: out/results.txt (110 pass + 4 expected AL2023 negatives), out/posture.txt, out/kyverno.txt (3 pass/3 fail as designed), mesh/istiod-rendered.yaml + ztunnel-rendered.yaml (helm template 1.28.0), out/ssm-snippet-test.txt, cfn-lint OK.
- Service mesh tab content written and ready: service-mesh.full.md (placeholders expanded).
TODO
- Service mesh tab (569dd476-c063 / body bda3ce4d-bf11, doc rev 2 at first read): plant pending blocks after mttvddjsrgd.0,
  fill 8 sections from service-mesh.full.md (lead paragraph replaces .36), then delete old blocks
  mttvddjsrgd.36 (h ef726c8e), .345 (920e413c), .352 (60c11187), .1511 (54a65ba2), .1521 (871e4fcb), .2317 (73ff417d), .2336 (eda4df26) with ifRev 2.
NEXT COMMAND
- mcp__claude_ai_Claude_Docs__read node bda3ce4d-bf11 {"kind":"view","sinceRev":2} then plant + fill.
