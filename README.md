![cableguard logo banner](./banner.png)

# Cableguard RODITVPN for managing Cableguard RODiT and VPN
This supplies the main userspace tooling for managing Rich Online Digital Tokens, and Cableguard TUN based VPNs

## License
This project is released under the [GPLv2](COPYING).
More information may be found at [WireGuard.com](https://www.wireguard.com/).**

## How to Install
Download with wget from:
https://cableguard.fra1.digitaloceanspaces.com/roditwallet.sh
https://cableguard.fra1.digitaloceanspaces.com/cgcvpn.sh
https://cableguard.fra1.digitaloceanspaces.com/cgsvpn-eth0.sh
https://cableguard.fra1.digitaloceanspaces.com/near-cli-rs_0.10.2-1_amd64.deb

Install near-cli-rs with
sudo apt install ./near-cli-rs_0.10.2-1_amd64.deb

Install jq with 
sudo apt install jq

## How to Use these scripts
Run the any script with the "help" option for instructions

CGRODITWALLET options:

Usage: ./roditwallet.sh [account_id] [Options]

Options:
-  ./roditwallet.sh                   : List of available accounts
-  ./roditwallet.sh *accountID*       : Lists the RODiT Ids in the account and its balance
-  ./roditwallet.sh *accountID* keys  : Displays the accountID and the Private Key of the account
-  ./roditwallet.sh *accountID* roditId: Displays the indicated RODiT
-  ./roditwallet.sh *fundingaccountId* *unitializedaccountId* init   : Initializes account with 0.01 NEAR from funding acount
-  ./roditwallet.sh *originaccountId*  *destinationaccountId* roditId : Sends RODiT from origin account to destination account
-  ./roditwallet.sh genaccount        : Creates a new uninitialized accountID

From a funded wallet you need to send 0.01 NEAR to each new account to prime it
For testnet use: https://wallet.testnet.near.org/

# Cableguard Ecosystem
- Cableguard RODITVPN: RODiT and VPN manager
- Cableguard TOOLS: local VPN tunnel configuration
- Cableguard TUN: VPN tunnels
- Cableguard FORGE: RODiT minter

---
<sub><sub><sub><sub>WireGuard is a registered trademark of Jason A. Donenfeld. Cableguard is not sponsored or endorsed by Jason A. Donenfeld.</sub></sub></sub></sub>
