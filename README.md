# Kefil — On-chain Trust Network for Agent IDs

"Kefil" means *guarantor* in Turkish. Agent ID holders vouch for agents they trust and flag the ones that misbehave. Vouching puts your own reputation at stake: if an agent you vouched for is flagged by 5 holders, your score drops too. Any dApp on BNB Chain can read the score in one call.

Built for the Binance Wallet × BNB Chain **Agent ID Hackathon**.

- **Live app:** https://neqro.github.io/kefil/
- **Demo video (60s):** https://neqro.github.io/kefil/demo.mp4
- **Contract (BNB Smart Chain, verified):** [`0xD9B175526469D1cD0094F25B65482b580514c215`](https://bscscan.com/address/0xD9B175526469D1cD0094F25B65482b580514c215#code)

## How Agent ID is used
- **Access control:** only Agent ID holders (`balanceOf > 0` on `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`) can vouch, flag or be scored.
- **Identity:** the trust score is bound to the Agent ID holder; if the ID is gone, the score is 0 and its vouches stop counting.
- **Composability:** `isTrusted(address, minScore)` lets other dApps gate airdrops, payments or agent-to-agent jobs.

## Score
`score = 10 × valid vouches − 10 × flags − 15 × vouches given to risky agents`
An agent with ≥ 5 flags is *risky*; its own vouches stop counting.

## Contract
- `vouch(target, note)` / `revokeVouch(target)` — max 20 active vouches per agent
- `flag(target, reason)` / `revokeFlag(target)`
- `trustScore`, `isTrusted`, `profile`, `vouchersOf`, `vouchedBy`, `isRisky`

## Permissions & safety
No owner, no admin, no upgrade, no pause, no token, no fees, no funds held. The contract cannot move any user asset. Every action is a normal transaction the user confirms in their own wallet. No QR login, no seed phrases or keys collected.

## Integrate
```solidity
interface IKefil { function isTrusted(address a, int256 minScore) external view returns (bool); }
require(IKefil(KEFIL).isTrusted(msg.sender, 30), "need 3+ trusted vouches");
```

## Dev
`npm i && node test.mjs` compiles with solc 0.8.24 and runs the tests on a local chain.
The mainnet deployment was compiled with solc 0.8.24, optimizer off, EVM cancun (as verified on BscScan).

License: MIT
