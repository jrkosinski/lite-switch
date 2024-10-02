import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("LiteSwitch", function () {
    let securityContext: any;
    let liteSwitch: any;
    let testToken: any;
    let admin: HardhatEthersSigner;
    let nonOwner: HardhatEthersSigner;
    let vaultAddress: HardhatEthersSigner;

    const DAO_ROLE = hre.ethers.keccak256(hre.ethers.encodeBytes32String("DAO_ROLE"));

    this.beforeEach(async () => {
        const [a1, a2, a3] = await hre.ethers.getSigners();
        admin = a1;
        nonOwner = a2;
        vaultAddress = a3;

        //deploy security context
        const SecurityContextFactory = await hre.ethers.getContractFactory("SecurityContext");
        securityContext = await SecurityContextFactory.deploy(admin.address);

        //deploy test token 
        const TestTokenFactory = await hre.ethers.getContractFactory("TestToken");
        testToken = await TestTokenFactory.deploy('XYZ', 'ZYX');

        //grant roles 
        const LiteSwitchFactory = await hre.ethers.getContractFactory("LiteSwitch");
        liteSwitch = await LiteSwitchFactory.deploy(securityContext.target, vaultAddress);
        await securityContext.connect(admin).grantRole(DAO_ROLE, vaultAddress);

        //grant token
        await testToken.mint(a2, 100000000);
    });


    describe("Deployment", function () {
        it("Should set the right DAO role", async function () {
            expect(await securityContext.hasRole(DAO_ROLE, admin.address)).to.be.false;
            expect(await securityContext.hasRole(DAO_ROLE, nonOwner.address)).to.be.false;
            expect(await securityContext.hasRole(DAO_ROLE, vaultAddress)).to.be.true;
        });
    });

    describe("Sweeping", function () {
        it("Can sweep non-token funds", async function () {
            expect(await admin.provider.getBalance(liteSwitch.target)).to.be.equal(0);
            const vaultInitialBalance = await admin.provider.getBalance(vaultAddress);

            //load non-token funds const signer = provider.getSigner(accounts[0]);
            const transaction = await nonOwner.sendTransaction({
                to: liteSwitch.target,
                value: hre.ethers.parseEther('2')
            });

            const switchBalance = await admin.provider.getBalance(liteSwitch.target);
            expect(switchBalance).to.be.greaterThan(0);

            //sweep to vault 
            expect(await admin.provider.getBalance(vaultAddress)).to.be.equal(vaultInitialBalance);
            await liteSwitch.sweep(hre.ethers.ZeroAddress);

            //balance has moved to vault
            expect(await admin.provider.getBalance(liteSwitch.target)).to.be.equal(0);
            expect(await admin.provider.getBalance(vaultAddress)).to.be.equal(switchBalance + vaultInitialBalance);
        });

        it("Can sweep token funds", async function () {
            expect(await admin.provider.getBalance(liteSwitch.target)).to.be.equal(0);
            const vaultInitialBalance = await testToken.balanceOf(vaultAddress);
            expect(vaultInitialBalance).to.equal(0);

            //transfer token 
            const transaction = await testToken.connect(nonOwner).transfer(liteSwitch.target, 100);

            const switchBalance = await testToken.balanceOf(liteSwitch.target);
            expect(switchBalance).to.equal(100);

            //sweep to vault 
            expect(await testToken.balanceOf(vaultAddress)).to.be.equal(vaultInitialBalance);

            await liteSwitch.sweep(testToken.target);

            //balance has moved to vault
            expect(await testToken.balanceOf(liteSwitch.target)).to.be.equal(0);
            expect(await testToken.balanceOf(vaultAddress)).to.be.equal(switchBalance + vaultInitialBalance);
        });
    });

    describe("Sweeping", function () {
        it("Can sweep non-token funds", async function () {
        });
    });
});
