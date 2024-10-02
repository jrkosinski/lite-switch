// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "./HasSecurityContext.sol"; 
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/* Encapsulates information about an incoming payment
*/
struct PaymentInput
{
    uint256 id;
    string orderId;
    address receiver;
    address payer;
    uint256 amount;
}

struct MultiPaymentInput 
{
    address currency; //token address, or 0x0 for native 
    PaymentInput[] payments;
}

/**
 * @title LiteSwitch
 * 
 * Takes in funds from marketplace, extracts a fee, and batches the payments for transfer
 * to the appropriate parties, holding the funds in escrow in the meantime. 
 * 
 * @author John R. Kosinski
 * LoadPipe 2024
 * All rights reserved. Unauthorized use prohibited.
 */
contract LiteSwitch is HasSecurityContext
{
    address public vaultAddress; 

    //EVENTS 
    event VaultAddressChanged (
        address newAddress,
        address changedBy
    );

    event PaymentReceived (
        string indexed orderId,
        address indexed to,
        address from, 
        address currency, 
        uint256 amount 
    );

    event PaymentSwept (
        address from, 
        address currency, 
        uint256 amount 
    );

    event PaymentSweepFailed (
        address from, 
        address currency, 
        uint256 amount 
    );
    
    /**
     * Constructor. 
     * 
     * Emits: 
     * - {HasSecurityContext-SecurityContextSet}
     * 
     * Reverts: 
     * - {ZeroAddressArgument} if the securityContext address is 0x0. 
     * 
     * @param securityContext Contract which will define & manage secure access for this contract. 
     * @param vault Recipient of the extracted fees. 
     */
    constructor(ISecurityContext securityContext, address vault) {
        _setSecurityContext(securityContext);
        if (vault == address(0)) 
            revert("InvalidVaultAddress");
        vaultAddress = vault;
    }

    /**
     * Sets the address to which fees are sent. 
     * 
     * Emits: 
     * - {MasterSwitch-VaultAddressChanged} 
     * 
     * Reverts: 
     * - 'AccessControl:' if caller is not authorized as DAO_ROLE. 
     * 
     * @param _vaultAddress The new address. 
     */
    function setVaultAddress(address _vaultAddress) public onlyRole(DAO_ROLE) {
        if (_vaultAddress != vaultAddress) {
            vaultAddress = _vaultAddress;
            emit VaultAddressChanged(_vaultAddress, msg.sender);
        }
    }
    
    /**
     * Allows multiple payments to be processed. 
     * 
     * @param multiPayments Array of payment definitions
     */
    function placeMultiPayments(MultiPaymentInput[] calldata multiPayments, bool immediateSweep) public payable {
        //approve tokens on behalf of 

        for(uint256 i=0; i<multiPayments.length; i++) {
            MultiPaymentInput memory multiPayment = multiPayments[i];
            address currency = multiPayment.currency; 
            uint256 amount = _getPaymentTotal(multiPayment);

            if (currency == address(0)) {
                //check that the amount matches
                if (msg.value < amount)
                    revert("InsufficientAmount");
            } 
            else {
                //transfer to self 
                IERC20 token = IERC20(currency);
                if (!token.transferFrom(msg.sender, address(this), amount))
                    revert('TokenPaymentFailed'); 
            }
                
            if (immediateSweep) {
                for(uint256 n=0; n<multiPayment.payments.length; n++) {
                    PaymentInput memory payment = multiPayment.payments[n];

                    //TODO: all payments can be consolidated if they're to the same receiver
                    if (_sweepAmount(
                        msg.sender, 
                        this.vaultAddress(), //right now hard-coded 
                        //payment.receiver, 
                        currency, 
                        payment.amount)
                    )
                        emit PaymentReceived(payment.orderId, payment.receiver, msg.sender, currency, amount);
                }
            }
        }
    }

    /**
     * Sweeps all funds of the specified type presently owned by the contract, into the 
     * predesignated vaultAddress. 
     * 
     * @param tokenAddressOrZero Address of the token to be swept, or 0x0 for native.
     */
    function sweep(address tokenAddressOrZero) public {
        uint256 amount = 0; 

        if (tokenAddressOrZero == address(0)) {
            amount = address(this).balance;
        } else {
            IERC20 token = IERC20(tokenAddressOrZero); 
            amount = token.balanceOf(address(this));
        }

        if (amount > 0)
            _sweepAmount(address(this), this.vaultAddress(), tokenAddressOrZero, amount);
    }

    function _getPaymentTotal(MultiPaymentInput memory input) internal pure returns (uint256) {
        uint256 output = 0;
        for(uint256 n=0; n<input.payments.length; n++) {
            output += input.payments[n].amount;
        }
        return output;
    }

    function _sweepAmount(address from, address to, address tokenAddressOrZero, uint256 amount) internal returns (bool) {
        bool success = false; 

        if (amount > 0) {
            if (tokenAddressOrZero == address(0)) {
                (success,) = payable(to).call{value: amount}("");
            } 
            else {
                IERC20 token = IERC20(tokenAddressOrZero); 
                success = token.transfer(to, amount);
            }

            if (success) {
                emit PaymentSwept(from, tokenAddressOrZero, amount);
            }
            else {
                emit PaymentSweepFailed(from, tokenAddressOrZero, amount);
            }
        }

        return success;
    }

    receive() external payable {}
}