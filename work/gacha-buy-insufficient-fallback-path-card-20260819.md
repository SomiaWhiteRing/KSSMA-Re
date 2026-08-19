# Gacha Buy Insufficient-Balance Compatibility Path Card, 2026-08-19

## Bounded Round

- **Frontier:** click friendship gacha -> `/connect/app/gacha/buy` -> insufficient balance ->
  client-visible continuation.
- **Success:** an insufficient purchase returns encrypted HTTP 200, writes no player data, and reuses the
  accepted gacha-select scene response instead of producing the client's generic network-failure dialog.
- **Non-goal:** this round does not claim to restore the original insufficient-balance dialog, change product
  prices, grant currency, award a card, or modify any native/client resource.
- **Stop:** if the real client still shows the network dialog or does not reach a usable gacha-select scene,
  retain the server/request artifact and stop before trying a second XML shape.

## New Observable

The live server log recorded this exact edge on 2026-08-19:

```text
/connect/app/gacha/select/getcontents
-> /connect/app/gacha/buy product_id=1 bulk=1 auto_build=1
-> GACHA_INSUFFICIENT_BALANCE: requires 200 friendshipPoint, available 0
```

The settlement guard correctly rejected the purchase before a save write. The route handler did not catch that
business error, so the common exception handler returned plain-text HTTP 500. `/connect/app/*` normally returns
AES-128-ECB ciphertext under HTTP 200; the old client therefore classified the undecryptable response as a
connection failure. Exploration and fairy battle remained healthy, ruling out a general transport outage.

## Accepted Path Reuse

- **Known-good entry:** main menu gacha button -> `/connect/app/gacha/select/getcontents`.
- **Known-good result:** encrypted HTTP 200 containing `error/code=0`, live `your_data`,
  `next_scene=9100`, and `body/gacha_select/xml_contents` produces the usable gacha selection page.
- **Native/request identity:** scene 9100 and the complete `gacha_select` model are already the accepted entry
  path; this round does not reconstruct an error dialog or a partial gacha UI.
- **Wrong-path connection point:** only the `GACHA_INSUFFICIENT_BALANCE` exception from
  `/connect/app/gacha/buy` is redirected to that complete response. Other exceptions still fail loudly.
- **Why full-path reuse:** the original generic business-error parser is known, but the call that presents its
  dialog scene is still not closed in `work/gacha-buy-failure-schema-card-20260810.md`. Reusing the complete
  accepted selection response avoids guessing an error XML or dialog producer edge.

## Candidate And Observable

One server variable changes: insufficient balance now returns the existing `createGachaSelectSkeletonXml`
response, encrypted with the established connect-app key. It logs:

```text
command=gacha_buy_rejected
nextScene=9100
rejectionCode=GACHA_INSUFFICIENT_BALANCE
requiredCost=<product cost>
availableBalance=<live balance>
saved=false
```

The automated server check must prove HTTP 200, decryptable `gacha_select`, absence of `gacha_buy`, and a
byte-identical player save. A real-client retry is still required to accept the visible scene transition.

## Client Acceptance

The user retried the live client after deployment and confirmed the flow was normal. This accepts the bounded
compatibility objective: the insufficient purchase no longer produces the generic connection-failure dialog and the
client remains usable. It does not accept an original-style insufficient-balance business dialog; that is the next
separate G1 round.

`ponytail:` this is a local compatibility fallback, not an original-server rejection contract. Replace it only
after the native dialog presentation edge and original response code/message are recovered.

## Superseded By Accepted Original Dialog

The compatibility objective remains accepted history, but it is no longer the product path. On 2026-08-19 the
native producer edge, parser-minimum code-1 response, visible `友情点不足` modal, dismissal back to the same gacha
page, route quietness, and byte-identical save were all accepted on MuMu A12. The server fallback and experiment
gate were then removed. Current evidence is in
`work/gacha-buy-original-balance-dialog-path-card-20260819.md`.
