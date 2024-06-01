![cableguard logo banner](./banner.png)

# Cableguard WALLET for managing Cableguard RODiT
This supplies the main userspace tooling for managing Rich Online Digital Tokens.

## License
This project is released under the [GPLv2](COPYING).
More information may be found at [WireGuard.com](https://www.wireguard.com/).**

## How to Install
Download with: wget https://cableguard.fra1.digitaloceanspaces.com/cgwalletinstall.sh

Make it executable

Run it. It will install the npm, nodejs, jq, and near cli dependencies to be able to handle RODiT with roditwallet.sh

## How to Use
Options:

Usage: ./walletsh/roditwallet.sh [account_id] [Options]

Options:
-  ./walletsh/roditwallet.sh                   : List of available accounts
-  ./walletsh/roditwallet.sh *accountID*       : Lists the RODiT Ids in the account and its balance
-  ./walletsh/roditwallet.sh *accountID* keys  : Displays the accountID and the Private Key of the account
-  ./walletsh/roditwallet.sh *accountID* roditId: Displays the indicated RODiT
-  ./walletsh/roditwallet.sh *fundingaccountId* *unitializedaccountId* init   : Initializes account with 0.01 NEAR from funding acount
-  ./walletsh/roditwallet.sh *originaccountId*  *destinationaccountId* roditId : Sends ROTD from origin account to destination account
-  ./walletsh/roditwallet.sh genaccount        : Creates a new uninitialized accountID

From a funded wallet you need to send 0.01 NEAR to each new account to prime it
For testnet use: https://wallet.testnet.near.org/

# Cableguard Ecosystem
# Cableguard Ecosystem
- Cableguard TUN: VPN tunnels
- Cableguard TOOLS: local VPN tunnel configuration
- Cableguard FORGE: RODiT minter
- Cableguard WALLET: RODiT manager
