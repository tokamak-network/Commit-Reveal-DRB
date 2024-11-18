# Copyright 2024 justin
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

-include .env

.PHONY: set-l1fee-mode all test clean deploy help install snapshot format anvil

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
			@echo "Usage:"
			@echo " make deploy [ARGS=...]\n	example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install OpenZeppelin/openzeppelin-contracts --no-commit && forge install Cyfrin/foundry-devops --no-commit

# Update Dependencies
update :; forge update

build :; forge build

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

anvil-titansepolia:; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --fork-url $(TITAN_SEPOLIA_URL) --block-time 1


#################### * scripts ####################

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast --legacy --gas-limit 9999999999999999999

ifeq ($(findstring --network thanossepolia,$(ARGS)), --network thanossepolia)
	NETWORK_ARGS := --rpc-url $(THANOS_SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url https://explorer.thanos-sepolia.tokamak.network/api --etherscan-api-key 11 -vv
endif
ifeq ($(findstring --network sepolia,$(ARGS)), --network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vv
endif
ifeq ($(findstring --network titansepolia,$(ARGS)), --network titansepolia)
	NETWORK_ARGS := --rpc-url $(TITAN_SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url $(TITAN_SEPOLIA_EXPLORER) -vv --legacy
endif
# ifeq ($(findstring --network titan,$(ARGS)), --network titan)
# 	NETWORK_ARGS := --rpc-url $(TITAN_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url $(TITAN_EXPLORER) -vv --legacy
# endif


deploy: deploy-drb deploy-consumer-example deploy-raretitle
# make deploy ARGS="--network thanossepolia"

deploy-drb:
	@forge script script/DeployDRBCoordinator.s.sol:DeployDRBCoordinator $(NETWORK_ARGS)

deploy-commit2reveal:
	@forge script script/DeployCommit2Reveal.s.sol:DeployCommit2Reveal $(NETWORK_ARGS)

deploy-commit2-reveal2:
	@forge script script/DeployCommit2Reveal2.s.sol:DeployCommit2Reveal2 $(NETWORK_ARGS)

deploy-consumer-example:
	@forge script script/DeployConsumerExample.s.sol:DeployConsumerExample $(NETWORK_ARGS)

deploy-raretitle:
	@forge script script/DeployRareTitle.s.sol:DeployRareTitle $(NETWORK_ARGS)

set-l1fee-mode:
	@forge script script/Interactions.s.sol:SetL1FeeCalculation $(NETWORK_ARGS)

three-deposit-activate:
	@forge script script/Interactions.s.sol:ThreeDepositAndActivate $(NETWORK_ARGS)

two-deposit-activate-real:
	@forge script script/Interactions.s.sol:TwoDepositAndActivateRealNetwork $(NETWORK_ARGS)

request-random:
	@forge script script/Interactions.s.sol:ConsumerRequestRandomNumber $(NETWORK_ARGS)

request-titansepolia:
	@forge script script/ConsumerInteractions.s.sol:Request $(NETWORK_ARGS)

ADDRESS := $()
request-random-with-address:
	@forge script script/Interactions.s.sol:ConsumerRequestRandomNumber $(NETWORK_ARGS) --sig "run(address)" $(ADDRESS)

ROUND := $()

TIMELEFT := $()

update-expiry:
	@forge script script/ConsumerInteractions.s.sol:UpdateGameExpiry $(NETWORK_ARGS) --sig "run(uint256)" $(TIMELEFT)

claim-prize:
	@forge script script/ConsumerInteractions.s.sol:ClaimPrize $(NETWORK_ARGS)

mint-claim:
	@forge script script/ConsumerInteractions.s.sol:MintandClaim $(NETWORK_ARGS)

commit:
	@forge script script/Interactions.s.sol:Commit $(NETWORK_ARGS) --sig "run(uint256)" $(ROUND) -vv

get-deposit:
	@forge script script/Interactions.s.sol:GetDepositAmount $(NETWORK_ARGS)

commit-with-address:
	@forge script script/Interactions.s.sol:Commit $(NETWORK_ARGS) --sig "run(uint256,address)" $(ROUND) $(ADDRESS) -vv

reveal:
	@forge script script/Interactions.s.sol:Reveal $(NETWORK_ARGS) --sig "run(uint256)" $(ROUND)

SENDER := $()
SECRET := $()

reveal-address-sender:
	@forge script script/Interactions.s.sol:Reveal $(NETWORK_ARGS) --sig "run(uint256,address,address,bytes32)" $(ROUND) $(ADDRESS) $(SENDER) $(SECRET)

reveal-with-address:
	@forge script script/Interactions.s.sol:Reveal $(NETWORK_ARGS) --sig "run(uint256,address)" $(ROUND) $(ADDRESS)

get-winner-info:
	@forge script script/ConsumerInteractions.s.sol:GetWinnerInfo $(NETWORK_ARGS)

SECOND := $()

blacklist:
	@forge script script/ConsumerInteractions.s.sol:BlackList $(NETWORK_ARGS)



increase:
	@forge script script/Interactions.s.sol:IncreaseTime $(NETWORK_ARGS) --sig "run(uint256)" $(SECOND)

refund:
	@forge script script/Interactions.s.sol:Refund $(NETWORK_ARGS) --sig "run(uint256)" $(ROUND)

verify-drb:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(uint256,uint256,uint256)" 826392287559752 250000000000000 150000000000000) \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url $(TITAN_EXPLORER) --rpc-url $(TITAN_RPC_URL) $(ADDRESS) DRBCoordinator

verify-commit2reveal:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(uint256,uint256,uint256,string,string)" 1000000000000000 10000000000000 10 "Tokamak DRB" "1") \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url $(TITAN_SEPOLIA_EXPLORER) --rpc-url $(TITAN_SEPOLIA_URL) $(ADDRESS) Commit2RevealDRB

verify-commit2reveal2:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(uint256,uint256,uint256,string,string)" 1000000000000000 10000000000000 10 "Tokamak DRB" "1") \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url $(TITAN_SEPOLIA_EXPLORER) --rpc-url $(TITAN_SEPOLIA_URL) $(ADDRESS) Commit2Reveal2DRB

verify-raretitle:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(address,uint256,address,uint256)" 0x78ACCa4E8269E6082D1C78B7386366feb7865fb4 86400 0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2 100000000000000000000) \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url $(TITAN_EXPLORER) --rpc-url $(TITAN_RPC_URL) $(ADDRESS) RareTitle

verify-consumer-example:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(address)" $(DRB)) \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url $(TITAN_SEPOLIA_EXPLORER) --rpc-url $(TITAN_SEPOLIA_URL) $(ADDRESS) ConsumerExample


test: test-drbCoordinator test-drbCoordinatorGas

test-drbCoordinator:
	@forge test --mp test/staging/DRBCoordinator.t.sol --gas-limit 9999999999999999999 -vv

test-drbCoordinatorGas:
	@forge test --mp test/unit/DRBCoordinatorGas.t.sol --gas-limit 9999999999999999999 -vv --isolate