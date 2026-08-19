# Main-menu player-level path card (2026-08-19)

## Frontier

```text
persisted profile.level
-> login/mainmenu-update header your_data
-> main-menu visible LV value
```

Success is a decrypted live response whose `town_level` equals the persisted player level. Rank progression,
friend-list rank labels, EXP curve changes, and save migration are outside this response-field correction.

## Accepted source and wrong mapping

- The admin and exploration level-up paths both read and write `playerSave.profile.level`; the current LAN save has
  `profile.level=6` and `profile.townLevel=1`.
- The bundled original `assets/bundle/local_battle_player.xml` separates `<town_level>6</town_level>` from
  `<rank>2</rank>`. They are not aliases.
- The current renderer incorrectly emits `<town_level>` from the stale compatibility field `profile.townLevel`,
  while also emitting `<rank>` from `profile.level`. The user's visible main menu consequently stays at `LV1`
  even though battle settlement logs `levelBefore=6/levelAfter=6`.

## Correct path reuse

All login and gameplay responses already share `renderYourDataXml`. Keep that complete header path and change only
the source of `<town_level>` to the authoritative `profile.level`. Do not mutate the save or duplicate level logic
inside login/mainmenu builders. Preserve `<rank>` unchanged until its independent value domain is recovered.

Observable:

- server self-check requires `town_level` to follow a non-default `profile.level`;
- restarted live `/connect/app/mainmenu` decrypts with `town_level=6` for `LonelyZero`;
- the client main menu visibly renders `LV6` after receiving a fresh response.
