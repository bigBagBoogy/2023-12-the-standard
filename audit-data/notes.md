## scope:

The onboarding data shows `7c9f84772eacb588c00a2add9f46aa93211a7132` as the commit 
hash that is in scope, however this no longer exists. Latest and only available commit
is commit 91132936cb09ef9bf82f38ab1106346e2ad60f91.

### this is found out by running:

```git show main```
commit 91132936cb09ef9bf82f38ab1106346e2ad60f91 (HEAD -> main, origin/main, origin/HEAD)
Author: Equious <76449140+Equious@users.noreply.github.com>
Date:   Thu Dec 28 02:08:32 2023 -0700

    Update README.md

diff --git a/README.md b/README.md
index 1cd52cd..a17ab3d 100644
--- a/README.md
+++ b/README.md
@@ -43,10 +43,10 @@ Secure your crypto assets, such as ETH, WBTC, ARB, LINK, & PAXG tokenized gold,
 
 All contracts at commit `7c9f84772eacb588c00a2add9f46aa93211a7132`
 
-- [SmartVaultV3](https://github.com/the-standard/cyfrin-audit/blob/7c9f84772eacb588c00a2add9f46aa93211a7132/contracts/SmartVaultV3.sol)
-- [SmartVaultManagerV5](https://github.com/the-standard/cyfrin-audit/blob/7c9f84772eacb588c00a2add9f46aa93211a7132/contracts/SmartVaultManagerV5.sol)
-- [LiquidationPool](https://github.com/the-standard/cyfrin-audit/blob/7c9f84772eacb588c00a2add9f46aa93211a7132/contracts/LiquidationPool.sol)
-- [LiquidationPoolManager](https://github.com/the-standard/cyfrin-audit/blob/7c9f84772eacb588c00a2add9f46aa93211a7132/contracts/LiquidationPoolManager.sol)
+- [SmartVaultV3]
+- [SmartVaultManagerV5]
+- [LiquidationPool]
+- [LiquidationPoolManager]

## protocol context:

On The standard you can create a deposit portfolio of ETH, WBTC, ARB, LINK, & PAXG (tokenized gold)
This portfolio will act as the collateral for taking out a loan in several fiat-pegged stable coins, 
which in turn can be put in the Camelot liquidity v3 pools in return for grail tokens

The Standard works with Camelot which offers liquidity pools that give an ROI of 15% + trading fees !?
the camelot protocol works with grail token the 15% roi will be for 10% in Grail token
Grail token is what collects fees on camelot
the other 5% will be in tst*** token, which also collects fees???

There supposedly is no lending interest, but when you borrow you do pay a 0.5% minting fee (You seem to "mint" the fiat-pegged stable coins)

However you don't need to deposit in camelot. You can also take 1000 EUROs loan and buy a bike.
The idea of this is basically tax avoidance. (since you never sold your BTC, there is no realized capital gains, but you CAN use the value of your BTC this way to buy something). Think Manhattan real estate

When repaying the loan, again you will have to pay 0.5% fee, So a full cycle will cost 1% in fees

*** tst token: is also used for governance. 
* TST USED ARE BURNED

a quick look at coin gecko

shows: https://www.coingecko.com/nl/coins/standard-token
- TheStandard Smart vaults are now launching on Arbitrum one and all liquidity will be moved and incentivised over on Camelot DEX. For more information, please visit this Twitter post.

 -According to GoPlus, the contract creator can make changes to the token contract such as disabling sells, changing fees, minting, transferring tokens etc. Exercise caution.



 ## Coverage of Files NOT 100%:

| File                      | % Stmts | % Branch | % Funcs | % Lines | Uncovered Lines   |
|---------------------------|---------|----------|---------|---------|-------------------|
| SmartVaultManagerV5.sol   | 96.3    | 92.86    | 94.12   | 97.5    | 90                |

## todo:
Make some diagrams to visualize the roles (owner, manager)


### It seems owner is an input param given upon deployment in CLI:
eg. ```hardhat run deploy.js --owner 0x123...```
