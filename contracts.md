# PrimordiumDAO Contract Deployments

All contracts follow the proxy-implementation upgradeable pattern. The address refers to the Ethereum mainnet deployment.

| Contract      | Description                     | Address |
| :-----------: | ------------------------------- | ------- |
| [PrimordiumExecutorV1](./src/executor/PrimordiumExecutorV1.sol)  | The treasury and executor contract for the DAO. Follows the Zodiac Avatar standard, with some modifications to include a timelock delay on all transactions. | Implementation: [0xdf2006d78E9E27b855070D440000Ba52E1C89C5d](https://etherscan.io/address/0xdf2006d78E9E27b855070D440000Ba52E1C89C5d)<br><br>Proxy: [0x6337b8630a3C641BEB0b7c26Fa542e31d6215c64](https://etherscan.io/address/0x6337b8630a3C641BEB0b7c26Fa542e31d6215c64) |
| [PrimordiumTokenV1](./src/token/PrimordiumTokenV1.sol) | The MUSHI token contract. An ERC20 token with Compound-style vote delegation to represent membership shares in PrimordiumDAO. | Implementation: [0xf6488B64C135777b6a4117AAB37F28e8b9b32f91](https://etherscan.io/address/0xf6488B64C135777b6a4117AAB37F28e8b9b32f91)<br><br>Proxy: [0x2aADC4ab6F8679C86f453a0FCc8B6B10d872335D](https://etherscan.io/address/0x2aADC4ab6F8679C86f453a0FCc8B6B10d872335D) |
| [PrimordiumSharesOnboarderV1](./src/onboarder/PrimordiumSharesOnboarderV1.sol) | The contract with onboarding functions to allow minting MUSHI membership tokens by depositing the quote asset according to the share price set by the DAO. | Implementation: [0xD512598238dd1B7a9B8DaCf806bE03AE8e848454](https://etherscan.io/address/0xD512598238dd1B7a9B8DaCf806bE03AE8e848454)<br><br>Proxy: [0xAf504e6811F0785eb0da73E5B252885cDE301d3C](https://etherscan.io/address/0xAf504e6811F0785eb0da73E5B252885cDE301d3C) |
| [PrimordiumGovernorV1](./src/governor/PrimordiumGovernorV1.sol) | The governor contract where proposals are created and voted on. Version 1 uses libraries to split the code due to code size restraints. | Implementation: [0xce956fE34807Ab0F604902993ab65486fEE24459](https://etherscan.io/address/0xce956fE34807Ab0F604902993ab65486fEE24459)<br><br>Proxy: [0xc384cb3bc23CB99826405b91c2E285e92E293Db8](https://etherscan.io/address/0xc384cb3bc23CB99826405b91c2E285e92E293Db8)<br><br>[GovernorBaseLogicV1](./src/governor/base/logic/GovernorBaseLogicV1.sol): [0x19803f54e919a668c1a5cea95863bc489484ffc9](https://etherscan.io/address/0x19803f54e919a668c1a5cea95863bc489484ffc9)<br><br>[ProposalVotingLogicV1](./src/governor/base/logic/ProposalVotingLogicV1.sol): [0xcfbd1f45ad411e763243b88136a265d2716d3cf5](https://etherscan.io/address/0xcfbd1f45ad411e763243b88136a265d2716d3cf5) |
| [DistributorV1](src/executor/extensions/DistributorV1.sol) | The contract for managing member distributions of ETH or ERC20 assets. Utilizes snapshots on the PrimordiumTokenV1 contract to track historical member balances for any given distribution. | Implementation: [0x0a3566Ee166475Fe791c33c0376919107b09320F](https://etherscan.io/address/0x0a3566Ee166475Fe791c33c0376919107b09320F)<br><br>Proxy: [0x540d08e2061ba64bB32B53C3D591faD841105c20](https://etherscan.io/address/0x540d08e2061ba64bB32B53C3D591faD841105c20) |





