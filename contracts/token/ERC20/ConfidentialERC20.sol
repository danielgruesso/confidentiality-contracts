// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/MpcCore.sol";

// The provided Solidity contract is an implementation of an ERC20 token standard with enhanced privacy features.
// It aims to ensure the confidentiality of token transactions through encryption techniques while maintaining compatibility with the ERC20 standard.
//
// Key Features:
// Privacy Enhancement:
// The contract utilizes encryption techniques to encrypt sensitive data such as token balances and allowances. Encryption is performed using both user-specific and system-wide encryption keys to safeguard transaction details.
// Encrypted Balances and Allowances:
// Token balances and allowances are stored in encrypted form within the contract's state variables. This ensures that sensitive information remains confidential and inaccessible to unauthorized parties.
// Integration with MPC Core:
// The contract leverages functionalities provided by an external component called MpcCore. This component likely implements cryptographic operations such as encryption, decryption, and signature verification using techniques like Multi-Party Computation (MPC).
// Token Transfer Methods:
// The contract provides multiple transfer methods, allowing token transfers in both encrypted and clear (unencrypted) forms. Transfers can occur between addresses with encrypted token values or clear token values.
// Approval Mechanism:
// An approval mechanism is implemented to allow token holders to grant spending permissions (allowances) to other addresses. Approvals are also encrypted to maintain transaction privacy.
abstract contract ConfidentialERC20 {
    // Events are emitted for token transfers (Transfer) and approvals (Approval). These events provide transparency and allow external observers to track token movements within the contract.
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Transfer(address indexed _from, address indexed _to);
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value
    );
    event Approval(address indexed _owner, address indexed _spender);

    string private _name;
    string private _symbol;
    uint8 private _decimals; // Sets the number of decimal places for token amounts. Here, _decimals is 5,
    // allowing for transactions with precision up to 0.00001 tokens.
    uint256 private _totalSupply;

    // Mapping of balances of the token holders
    // The balances are stored encrypted by the system aes key
    mapping(address => utUint64) internal balances;
    // Mapping of allowances of the token holders
    mapping(address => mapping(address => utUint64)) private allowances;

    // Create the contract with the name and symbol. Assign the initial supply of tokens to the contract creator.
    // params: name: the name of the token
    //         symbol: the symbol of the token
    //         initialSupply: the initial supply of the token assigned to the contract creator
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    // The function returns the encrypted account balance utilizing the user's secret key.
    // Since the balance is initially encrypted internally using the system's AES key, the user cannot access it.
    // Thus, the balance undergoes re-encryption using the user's secret key.
    // As a result, the function is not designated as a "view" function.
    function balanceOf() public view virtual returns (ctUint64 balance) {
        return balances[msg.sender].userCiphertext;
    }

    // Transfers the amount of tokens given inside the IT (encrypted and signed value) to address _to
    // params: _to: the address to transfer to
    //         _itCT: the encrypted value of the amount to transfer
    //         _itSignature: the signature of the amount to transfer
    //         revealRes: indicates if we should reveal the result of the transfer
    // returns: In case revealRes is true, returns the result of the transfer. In case revealRes is false, always returns true
    function transfer(
        address _to,
        ctUint64 _itCT,
        bytes calldata _itSignature,
        bool revealRes
    ) public virtual returns (bool success) {
        // Create IT from ciphertext and signature
        itUint64 memory it;
        it.ciphertext = _itCT;
        it.signature = _itSignature;
        // Verify the IT and transfer the value
        gtBool result = contractTransfer(_to, MpcCore.validateCiphertext(it));
        if (revealRes) {
            return MpcCore.decrypt(result);
        } else {
            return true;
        }
    }

    // Transfers the amount of tokens to address _to
    // params: _to: the address to transfer to
    //         _value: the value of the amount to transfer
    //         revealRes: indicates if we should reveal the result of the transfer
    // returns: In case revealRes is true, returns the result of the transfer. In case revealRes is false, always returns true
    function transfer(
        address _to,
        uint64 _value,
        bool revealRes
    ) public virtual returns (bool success) {
        gtBool result = contractTransferClear(_to, _value);

        if (revealRes) {
            return MpcCore.decrypt(result);
        } else {
            return true;
        }
    }

    // Transfers the amount of tokens given inside the encrypted value to address _to
    // params: _to: the address to transfer to
    //         _value: the encrypted value of the amount to transfer
    // returns: The encrypted result of the transfer.
    function contractTransfer(
        address _to,
        gtUint64 _value
    ) public virtual returns (gtBool success) {
        (gtUint64 fromBalance, gtUint64 toBalance) = getBalances(
            msg.sender,
            _to
        );
        (
            gtUint64 newFromBalance,
            gtUint64 newToBalance,
            gtBool result
        ) = MpcCore.transfer(fromBalance, toBalance, _value);

        emit Transfer(msg.sender, _to);
        setNewBalances(msg.sender, _to, newFromBalance, newToBalance);

        return result;
    }

    // Transfers the amount of tokens to address _to
    // params: _to: the address to transfer to
    //         _value: the value of the amount to transfer
    // returns: The encrypted result of the transfer.
    function contractTransferClear(
        address _to,
        uint64 _value
    ) public virtual returns (gtBool success) {
        (gtUint64 fromBalance, gtUint64 toBalance) = getBalances(
            msg.sender,
            _to
        );
        (
            gtUint64 newFromBalance,
            gtUint64 newToBalance,
            gtBool result
        ) = MpcCore.transfer(fromBalance, toBalance, _value);

        emit Transfer(msg.sender, _to, _value);
        setNewBalances(msg.sender, _to, newFromBalance, newToBalance);

        return result;
    }

    // Transfers the amount of tokens given inside the IT (encrypted and signed value) from address _from to address _to
    // params: _from: the address to transfer from
    //         __to: the address to transfer to
    //         _itCT: the encrypted value of the amount to transfer
    //         _itSignature: the signature of the amount to transfer
    //         revealRes: indicates if we should reveal the result of the transfer
    // returns: In case revealRes is true, returns the result of the transfer. In case revealRes is false, always returns true
    function transferFrom(
        address _from,
        address _to,
        ctUint64 _itCT,
        bytes calldata _itSignature,
        bool revealRes
    ) public virtual returns (bool success) {
        // Create IT from ciphertext and signature
        itUint64 memory it;
        it.ciphertext = _itCT;
        it.signature = _itSignature;
        // Verify the IT and transfer the value
        gtBool result = contractTransferFrom(
            _from,
            _to,
            MpcCore.validateCiphertext(it)
        );
        if (revealRes) {
            return MpcCore.decrypt(result);
        } else {
            return true;
        }
    }

    // Transfers the amount of tokens from address _from to address _to
    // params: _from: the address to transfer from
    //         __to: the address to transfer to
    //         _value: the value of the amount to transfer
    //         revealRes: indicates if we should reveal the result of the transfer
    // returns: In case revealRes is true, returns the result of the transfer. In case revealRes is false, always returns true
    function transferFrom(
        address _from,
        address _to,
        uint64 _value,
        bool revealRes
    ) public virtual returns (bool success) {
        gtBool result = contractTransferFromClear(_from, _to, _value);
        if (revealRes) {
            return MpcCore.decrypt(result);
        } else {
            return true;
        }
    }

    // Transfers the amount of tokens given inside the encrypted value from address _from to address _to
    // params: _from: the address to transfer from
    //         _to: the address to transfer to
    //         _value: the encrypted value of the amount to transfer
    // returns: The encrypted result of the transfer.
    function contractTransferFrom(
        address _from,
        address _to,
        gtUint64 _value
    ) public virtual returns (gtBool success) {
        (gtUint64 fromBalance, gtUint64 toBalance) = getBalances(_from, _to);
        gtUint64 allowanceAmount = MpcCore.onBoard(getGTAllowance(_from, _to));
        (
            gtUint64 newFromBalance,
            gtUint64 newToBalance,
            gtBool result,
            gtUint64 newAllowance
        ) = MpcCore.transferWithAllowance(
                fromBalance,
                toBalance,
                _value,
                allowanceAmount
            );

        setApproveValue(_from, _to, newAllowance);
        emit Transfer(_from, _to);
        setNewBalances(_from, _to, newFromBalance, newToBalance);

        return result;
    }

    // Transfers the amount of tokens from address _from to address _to
    // params: _from: the address to transfer from
    //         _to: the address to transfer to
    //         _value: the value of the amount to transfer
    // returns: The encrypted result of the transfer.
    function contractTransferFromClear(
        address _from,
        address _to,
        uint64 _value
    ) public virtual returns (gtBool success) {
        (gtUint64 fromBalance, gtUint64 toBalance) = getBalances(_from, _to);
        gtUint64 allowanceAmount = MpcCore.onBoard(getGTAllowance(_from, _to));
        (
            gtUint64 newFromBalance,
            gtUint64 newToBalance,
            gtBool result,
            gtUint64 newAllowance
        ) = MpcCore.transferWithAllowance(
                fromBalance,
                toBalance,
                _value,
                allowanceAmount
            );

        setApproveValue(_from, _to, newAllowance);
        emit Transfer(_from, _to, _value);
        setNewBalances(_from, _to, newFromBalance, newToBalance);

        return result;
    }

    function _mint(address account, uint64 value) internal {
        ctUint64 balance = balances[account].ciphertext;

        _totalSupply += value;

        gtUint64 gtBalance = ctUint64.unwrap(balance) == 0 ? MpcCore.setPublic64(0):MpcCore.onBoard(balance);
        gtUint64 gtNewBalance = MpcCore.add(gtBalance, MpcCore.setPublic64(value));
        balances[account] = MpcCore.offBoardCombined(gtNewBalance, account);
    }

    // Returns the encrypted balances of the two addresses
    function getBalances(
        address _from,
        address _to
    ) private returns (gtUint64, gtUint64) {
        ctUint64 fromBalance = balances[_from].ciphertext;
        ctUint64 toBalance = balances[_to].ciphertext;

        gtUint64 gtFromBalance;
        gtUint64 gtToBalance;
        if (ctUint64.unwrap(fromBalance) == 0) {
            // 0 means that no allowance has been set
            gtFromBalance = MpcCore.setPublic64(0);
        } else {
            gtFromBalance = MpcCore.onBoard(fromBalance);
        }

        if (ctUint64.unwrap(toBalance) == 0) {
            // 0 means that no allowance has been set
            gtToBalance = MpcCore.setPublic64(0);
        } else {
            gtToBalance = MpcCore.onBoard(toBalance);
        }

        return (gtFromBalance, gtToBalance);
    }

    // Sets the new encrypted balances of the two addresses
    function setNewBalances(
        address _from,
        address _to,
        gtUint64 newFromBalance,
        gtUint64 newToBalance
    ) private {
        // Convert the gtUInt64 to ctUint64 and store it in the balances mapping
        balances[_from] = MpcCore.offBoardCombined(newFromBalance, _from);
        balances[_to] = MpcCore.offBoardCombined(newToBalance, _to);
    }

    // Sets the new allowance given inside the IT (encrypted and signed value) of the spender
    function approve(
        address _spender,
        ctUint64 _itCT,
        bytes calldata _itSignature
    ) public virtual returns (bool success) {
        // Create IT using the given CT and signature
        itUint64 memory it;
        it.ciphertext = _itCT;
        it.signature = _itSignature;
        return approve(_spender, MpcCore.validateCiphertext(it));
    }

    // Sets the new encrypted allowance of the spender
    function approve(
        address _spender,
        gtUint64 _value
    ) public virtual returns (bool success) {
        address owner = msg.sender;
        setApproveValue(owner, _spender, _value);
        emit Approval(owner, _spender);
        return true;
    }

    // Sets the new allowance of the spender
    function approveClear(
        address _spender,
        uint64 _value
    ) public virtual returns (bool success) {
        address owner = msg.sender;
        gtUint64 gt = MpcCore.setPublic64(_value);
        setApproveValue(owner, _spender, gt);
        emit Approval(owner, _spender, _value);
        return true;
    }

    // Returns the encrypted allowance of the spender. The encryption is done using the msg.sender aes key
    function allowance(
        address _owner,
        address _spender
    ) public view virtual returns (ctUint64 remaining) {
        require(_owner == msg.sender || _spender == msg.sender);

        return allowances[_owner][_spender].userCiphertext;
    }

    // Returns the encrypted allowance of the spender. The encryption is done using the system aes key
    function getGTAllowance(
        address _owner,
        address _spender
    ) private returns (ctUint64 remaining) {
        if (ctUint64.unwrap(allowances[_owner][_spender].ciphertext) == 0) {
            // 0 means that no allowance has been set
            gtUint64 zero = MpcCore.setPublic64(0);
            return MpcCore.offBoard(zero);
        } else {
            return allowances[_owner][_spender].ciphertext;
        }
    }

    // Sets the new encrypted allowance of the spender
    function setApproveValue(
        address _owner,
        address _spender,
        gtUint64 _value
    ) private {
        allowances[_owner][_spender] = MpcCore.offBoardCombined(_value, _owner);
    }
}
