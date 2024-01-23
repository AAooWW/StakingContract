import { ethers } from "hardhat";
import { MyToken1, Staking } from "../typechain-types";

async function main() {

  let staking: Staking;
  let myToken1: MyToken1;

  const myToken1Factory = await ethers.getContractFactory("MyToken1");
  myToken1 = (await myToken1Factory.deploy()) as MyToken1;
  await myToken1.deployed();

  const stakingFactory = await ethers.getContractFactory("Staking");
  staking = (await stakingFactory.deploy(myToken1.address, 100)) as Staking;
  await staking.deployed();

  console.log(
    ` `
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
