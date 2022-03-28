
const start = new Date('Sun Mar 13 2022 20:00:00 GMT+0700 (Indochina Time)')
const cliffDuration = 30 * 24 * 60 * 60 // 30 days
const cliffDuration2 = 90 * 24 * 60 * 60 // 90 days
const duration = 485 * 60 * 60 * 60 // 30 days + 90 days + 365 days
const firstReleasePercent = 5
const secondsPerSlice = 30 * 24 * 60 * 60 // 30 days

async function main() {
    // We get the contract to deploy
    const contract = await ethers.getContractFactory('DFHVestingToken');
    console.log('Deploying DFHVestingToken...');
    const token = await contract.deploy(
      start.getTime() / 1e3,
      cliffDuration,
      cliffDuration2,
      duration,
      firstReleasePercent,
      secondsPerSlice
    );
    await token.deployed();
    console.log('DFHVestingToken deployed to:', token.address);
    console.log(`Please enter this command below to verify your contract:`)
    console.log(`npx hardhat verify --network testnet ${token.address} ${start.getTime() / 1e3} ${cliffDuration} ${cliffDuration2} ${duration} ${firstReleasePercent} ${secondsPerSlice}`)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });