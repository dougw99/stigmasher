# TODO — appservice-stig scaffold

1. Obtain the unfilled App Service STIG `.cklb` and place it in `_config\`.
2. Read every rule's check_content; derive key events; write
   `rules\rules.md` (key events + decision tables, see scaffolding notes there).
3. Implement `scripts\collect_azure.ps1` for the App Service resource's evidence.
4. Exercise stages 01-05 end-to-end on a real App Service resource.
5. Distill stage-03 learnings into `_config\overrides.md` and rules.md.
