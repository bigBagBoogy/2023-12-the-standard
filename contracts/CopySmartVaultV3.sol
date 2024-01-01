// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/interfaces/IEUROs.sol";
import "contracts/interfaces/IPriceCalculator.sol";
import "contracts/interfaces/ISmartVault.sol";
import "contracts/interfaces/ISmartVaultManagerV3.sol";
import "contracts/interfaces/ISwapRouter.sol";
import "contracts/interfaces/ITokenManager.sol";
import "contracts/interfaces/IWETH.sol";

/**
 * @title SmartVaultV3
 * @dev SmartVaultV3 is a smart contract that manages collateral and EUROs minting/burning.
 */

contract SmartVaultV3 is ISmartVault {
    using SafeERC20 for IERC20;

    // Error messages
    string private constant INVALID_USER = "err-invalid-user";
    string private constant UNDER_COLL = "err-under-coll";

    // Contract version and type
    uint8 private constant version = 2;
    bytes32 private constant vaultType = bytes32("EUROs");

    // Native token symbol
    bytes32 private immutable NATIVE;

    // Immutable addresses
    address public immutable manager;
    IEUROs public immutable EUROs;
    IPriceCalculator public immutable calculator;

    // Mutable state variables
    address public owner;
    uint256 private minted;
    bool private liquidated;

    // Events
    event CollateralRemoved(bytes32 symbol, uint256 amount, address to);
    event AssetRemoved(address token, uint256 amount, address to);
    event EUROsMinted(address to, uint256 amount, uint256 fee);
    event EUROsBurned(uint256 amount, uint256 fee);

    /**
     * @dev Constructor to initialize the SmartVaultV3 contract.
     * @param _native The symbol of the native token.
     * @param _manager The address of the vault manager contract.
     * @param _owner The initial owner of the contract.
     * @param _euros The address of the EUROs token contract.
     * @param _priceCalculator The address of the price calculator contract.
     */
    constructor(bytes32 _native, address _manager, address _owner, address _euros, address _priceCalculator) {
        NATIVE = _native;
        owner = _owner;
        manager = _manager;
        EUROs = IEUROs(_euros);
        calculator = IPriceCalculator(_priceCalculator);
    }
    // Modifiers

    modifier onlyVaultManager() {
        require(msg.sender == manager, INVALID_USER);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, INVALID_USER);
        _;
    }
    /**
     * @dev Modifier to check if the specified amount has been minted.
     * @param _amount The amount to check for minting.
     */

    modifier ifMinted(uint256 _amount) {
        require(minted >= _amount, "err-insuff-minted");
        _;
    }
    /**
     * @dev Modifier to check if the contract has not been liquidated.
     */

    modifier ifNotLiquidated() {
        require(!liquidated, "err-liquidated");
        _;
    }

    /**
     * @dev Internal function to get the token manager interface.
     * @return ITokenManager The token manager interface.
     */
    function getTokenManager() private view returns (ITokenManager) {
        return ITokenManager(ISmartVaultManagerV3(manager).tokenManager());
    }

    /**
     * @dev Internal function to calculate the total Euro value of all accepted tokens as collateral.
     * return -> uint256 The total Euro value of all accepted tokens.
     */

    function euroCollateral() private view returns (uint256 euros) {
        ITokenManager.Token[] memory acceptedTokens = getTokenManager().getAcceptedTokens();
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            ITokenManager.Token memory token = acceptedTokens[i];
            euros += calculator.tokenToEurAvg(token, getAssetBalance(token.symbol, token.addr));
        }
    }

    /**
     * @dev Internal function to calculate the maximum amount of EUROs that can be minted based on collateral.
     * @return uint256 The maximum mintable EUROs amount.
     */
    function maxMintable() private view returns (uint256) {
        return euroCollateral() * ISmartVaultManagerV3(manager).HUNDRED_PC()
            / ISmartVaultManagerV3(manager).collateralRate();
    }

    /**
     * @dev Internal function to get the balance of a specific asset in the vault.
     * @param _symbol The symbol of the asset.
     * @param _tokenAddress The address of the asset's token contract.
     * return -> uint256 The balance of the specified asset.
     */
    /**
     * @dev Internal function to get the balance of a specific asset in the vault.
     * @param _symbol The symbol of the asset.
     * @param _tokenAddress The address of the asset's token contract.
     * return -> uint256 The balance of the specified asset.
     */
    function getAssetBalance(bytes32 _symbol, address _tokenAddress) private view returns (uint256 amount) {
        return _symbol == NATIVE ? address(this).balance : IERC20(_tokenAddress).balanceOf(address(this));
    }

    /**
     * @dev Internal function to get the details of all assets held by the vault.
     * @return Asset[] An array of Asset structures representing the details of each asset.
     */
    function getAssets() private view returns (Asset[] memory) {
        ITokenManager.Token[] memory acceptedTokens = getTokenManager().getAcceptedTokens();
        Asset[] memory assets = new Asset[](acceptedTokens.length);
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            ITokenManager.Token memory token = acceptedTokens[i];
            uint256 assetBalance = getAssetBalance(token.symbol, token.addr);
            assets[i] = Asset(token, assetBalance, calculator.tokenToEurAvg(token, assetBalance));
        }
        return assets;
    }

    /**
     * @dev External function to get the current status of the vault.
     * @return Status A struct containing various status parameters of the vault.
     */
    function status() external view returns (Status memory) {
        return
            Status(address(this), minted, maxMintable(), euroCollateral(), getAssets(), liquidated, version, vaultType);
    }

    /**
     * @dev Public function to check if the vault is undercollateralized.
     * @return bool True if the vault is undercollateralized, false otherwise.
     */
    function undercollateralised() public view returns (bool) {
        return minted > maxMintable();
    }

    /**
     * @dev Internal function to liquidate the native token held by the vault.
     */
    function liquidateNative() private {
        if (address(this).balance != 0) {
            (bool sent,) = payable(ISmartVaultManagerV3(manager).protocol()).call{value: address(this).balance}("");
            require(sent, "err-native-liquidate");
        }
    }

    /**
     * @dev Internal function to liquidate an ERC20 token held by the vault.
     * @param _token The ERC20 token to be liquidated.
     */
    function liquidateERC20(IERC20 _token) private {
        if (_token.balanceOf(address(this)) != 0) {
            _token.safeTransfer(ISmartVaultManagerV3(manager).protocol(), _token.balanceOf(address(this)));
        }
    }

    /**
     * @dev External function to liquidate the vault, transferring remaining assets to the protocol.
     * @notice The function must be called only by the vault manager.
     */
    function liquidate() external onlyVaultManager {
        require(undercollateralised(), "err-not-liquidatable");
        liquidated = true;
        minted = 0;
        liquidateNative();
        ITokenManager.Token[] memory tokens = getTokenManager().getAcceptedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].symbol != NATIVE) liquidateERC20(IERC20(tokens[i].addr));
        }
    }

    /**
     * @dev Fallback function to receive native tokens sent to the contract.
     */
    receive() external payable {}

    /**
     * @dev Internal function to check if collateral removal is allowed for a specific token and amount.
     * @param _token The token for which collateral removal is checked.
     * @param _amount The amount of collateral to be removed.
     * @return bool True if collateral removal is allowed, false otherwise.
     */
    function canRemoveCollateral(ITokenManager.Token memory _token, uint256 _amount) private view returns (bool) {
        if (minted == 0) return true;
        uint256 currentMintable = maxMintable();
        uint256 eurValueToRemove = calculator.tokenToEurAvg(_token, _amount);
        return currentMintable >= eurValueToRemove && minted <= currentMintable - eurValueToRemove;
    }

    /**
     * @dev External function to remove native collateral and transfer it to the specified address.
     * @param _amount The amount of native collateral to be removed.
     * @param _to The address to which the collateral will be transferred.
     */
    function removeCollateralNative(uint256 _amount, address payable _to) external onlyOwner {
        require(canRemoveCollateral(getTokenManager().getToken(NATIVE), _amount), UNDER_COLL);
        (bool sent,) = _to.call{value: _amount}("");
        require(sent, "err-native-call");
        emit CollateralRemoved(NATIVE, _amount, _to);
    }

    /**
     * @dev External function to remove collateral of a specific token and transfer it to the specified address.
     * @param _symbol The symbol of the token for which collateral will be removed.
     * @param _amount The amount of collateral to be removed.
     * @param _to The address to which the collateral will be transferred.
     */
    function removeCollateral(bytes32 _symbol, uint256 _amount, address _to) external onlyOwner {
        ITokenManager.Token memory token = getTokenManager().getToken(_symbol);
        require(canRemoveCollateral(token, _amount), UNDER_COLL);
        IERC20(token.addr).safeTransfer(_to, _amount);
        emit CollateralRemoved(_symbol, _amount, _to);
    }

    /**
     * @dev External function to remove assets of a specific ERC20 token and transfer them to the specified address.
     * @param _tokenAddr The address of the ERC20 token for which assets will be removed.
     * @param _amount The amount of assets to be removed.
     * @param _to The address to which the assets will be transferred.
     */
    function removeAsset(address _tokenAddr, uint256 _amount, address _to) external onlyOwner {
        ITokenManager.Token memory token = getTokenManager().getTokenIfExists(_tokenAddr);
        if (token.addr == _tokenAddr) require(canRemoveCollateral(token, _amount), UNDER_COLL);
        IERC20(_tokenAddr).safeTransfer(_to, _amount);
        emit AssetRemoved(_tokenAddr, _amount, _to);
    }

    /**
     * @dev Internal function to check if the vault is fully collateralized after a specified amount is added.
     * @param _amount The amount to check for full collateralization.
     * @return bool True if the vault is fully collateralized, false otherwise.
     */
    function fullyCollateralised(uint256 _amount) private view returns (bool) {
        return minted + _amount <= maxMintable();
    }

    /**
     * @dev External function to mint EUROs and distribute them to the specified address, collecting minting fees.
     * @param _to The address to which EUROs will be minted.
     * @param _amount The amount of EUROs to mint.
     */
    // q who mints? the vault manager? this is a smart contract
    // is the vault manager set to be the owner? or does the vault manager deploy THIS smart contract?
    function mint(address _to, uint256 _amount) external onlyOwner ifNotLiquidated {
        uint256 fee = _amount * ISmartVaultManagerV3(manager).mintFeeRate() / ISmartVaultManagerV3(manager).HUNDRED_PC();
        require(fullyCollateralised(_amount + fee), UNDER_COLL);
        // It calculates and updates the minted amount (minted variable) by adding the minted amount and the minting fee.
        minted = minted + _amount + fee;
        // it calls the mint function of the EUROs contract to create new EUROs tokens for the specified recipient (_to).
        EUROs.mint(_to, _amount);
        // It calls the mint function of the EUROs contract again to create new EUROs tokens for the protocol, representing the minting fee.
        EUROs.mint(ISmartVaultManagerV3(manager).protocol(), fee);
        emit EUROsMinted(_to, _amount, fee);
    }

    /**
     * @dev External function to burn EUROs, collecting burning fees.
     * @param _amount The amount of EUROs to burn.
     */
    function burn(uint256 _amount) external ifMinted(_amount) {
        uint256 fee = _amount * ISmartVaultManagerV3(manager).burnFeeRate() / ISmartVaultManagerV3(manager).HUNDRED_PC();
        minted = minted - _amount;
        EUROs.burn(msg.sender, _amount);
        IERC20(address(EUROs)).safeTransferFrom(msg.sender, ISmartVaultManagerV3(manager).protocol(), fee);
        emit EUROsBurned(_amount, fee);
    }

    /**
     * @dev Internal function to get the token details for a given symbol.
     * @param _symbol The symbol of the token.
     * return -> ITokenManager.Token The details of the token.
     */
    function getToken(bytes32 _symbol) private view returns (ITokenManager.Token memory _token) {
        ITokenManager.Token[] memory tokens = getTokenManager().getAcceptedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].symbol == _symbol) _token = tokens[i];
        }
        require(_token.symbol != bytes32(0), "err-invalid-swap");
    }

    /**
     * @dev Internal function to get the swap address for a given token symbol.
     * @param _symbol The symbol of the token.
     * @return address The address used for swapping, either the token address or WETH address.
     */
    function getSwapAddressFor(bytes32 _symbol) private view returns (address) {
        ITokenManager.Token memory _token = getToken(_symbol);
        return _token.addr == address(0) ? ISmartVaultManagerV3(manager).weth() : _token.addr;
    }

    /**
     * @dev Internal function to execute a native token swap and pay the specified swap fee.
     * @param _params Swap parameters for the native token.
     * @param _swapFee The swap fee to be paid in native tokens.
     */
    function executeNativeSwapAndFee(ISwapRouter.ExactInputSingleParams memory _params, uint256 _swapFee) private {
        (bool sent,) = payable(ISmartVaultManagerV3(manager).protocol()).call{value: _swapFee}("");
        require(sent, "err-swap-fee-native");
        ISwapRouter(ISmartVaultManagerV3(manager).swapRouter2()).exactInputSingle{value: _params.amountIn}(_params);
    }

    /**
     * @dev Internal function to execute an ERC20 token swap and pay the specified swap fee.
     * @param _params Swap parameters for the ERC20 token.
     * @param _swapFee The swap fee to be paid in ERC20 tokens.
     */
    function executeERC20SwapAndFee(ISwapRouter.ExactInputSingleParams memory _params, uint256 _swapFee) private {
        IERC20(_params.tokenIn).safeTransfer(ISmartVaultManagerV3(manager).protocol(), _swapFee);
        IERC20(_params.tokenIn).safeApprove(ISmartVaultManagerV3(manager).swapRouter2(), _params.amountIn);
        ISwapRouter(ISmartVaultManagerV3(manager).swapRouter2()).exactInputSingle(_params);
        IWETH weth = IWETH(ISmartVaultManagerV3(manager).weth());
        // convert potentially received WETH to ETH
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) weth.withdraw(wethBalance);
    }

    /**
     * @dev Internal function to calculate the minimum amount out for a swap based on collateral requirements.
     * @param _inTokenSymbol The symbol of the input token.
     * @param _outTokenSymbol The symbol of the output token.
     * @param _amount The amount to be swapped.
     * @return uint256 The calculated minimum amount out.
     */
    function calculateMinimumAmountOut(bytes32 _inTokenSymbol, bytes32 _outTokenSymbol, uint256 _amount)
        private
        view
        returns (uint256)
    {
        ISmartVaultManagerV3 _manager = ISmartVaultManagerV3(manager);
        uint256 requiredCollateralValue = minted * _manager.collateralRate() / _manager.HUNDRED_PC();
        uint256 collateralValueMinusSwapValue =
            euroCollateral() - calculator.tokenToEur(getToken(_inTokenSymbol), _amount);
        return collateralValueMinusSwapValue >= requiredCollateralValue
            ? 0
            : calculator.eurToToken(getToken(_outTokenSymbol), requiredCollateralValue - collateralValueMinusSwapValue);
    }

    /**
     * @dev External function to swap assets from one token to another.
     * @param _inToken The symbol of the input token.
     * @param _outToken The symbol of the output token.
     * @param _amount The amount of input tokens to be swapped.
     */
    function swap(bytes32 _inToken, bytes32 _outToken, uint256 _amount) external onlyOwner {
        uint256 swapFee =
            _amount * ISmartVaultManagerV3(manager).swapFeeRate() / ISmartVaultManagerV3(manager).HUNDRED_PC();
        address inToken = getSwapAddressFor(_inToken);
        uint256 minimumAmountOut = calculateMinimumAmountOut(_inToken, _outToken, _amount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: inToken,
            tokenOut: getSwapAddressFor(_outToken),
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount - swapFee,
            amountOutMinimum: minimumAmountOut,
            sqrtPriceLimitX96: 0
        });
        inToken == ISmartVaultManagerV3(manager).weth()
            ? executeNativeSwapAndFee(params, swapFee)
            : executeERC20SwapAndFee(params, swapFee);
    }

    /**
     * @dev External function to set a new owner for the vault.
     * @param _newOwner The address of the new owner.
     * @notice The function must be called only by the vault manager.
     */
    // q vaultManager == owner?
    function setOwner(address _newOwner) external onlyVaultManager {
        owner = _newOwner;
    }
}

// This smart contract is an implementation of a decentralized vault (SmartVaultV3) that manages collateral and mints a stablecoin (EUROs) based on the collateral provided. The primary features and functionalities include:

// Collateral Management:

// Accepts various ERC-20 tokens and native (ETH) as collateral.
// Calculates the total value of the collateral in euros using a price calculator.
// Tracks the maximum amount of EUROs that can be minted based on the collateral ratio.
// Minting and Burning:

// Allows the owner to mint EUROs by providing collateral.
// Applies a minting fee, and the minted EUROs are distributed to the owner and the protocol.
// Supports burning EUROs, applying a burning fee, and sending the corresponding collateral back to the owner.
// Liquidation:

// Enables the vault manager to liquidate the collateral in case the vault becomes undercollateralized.
// Liquidation includes converting native token (ETH) and other ERC-20 tokens to EUROs and transferring them to the protocol.
// Asset Removal:

// Allows the owner to remove collateral and assets under certain conditions.
// Checks if the removal of collateral maintains the required collateral ratio.
// Swapping:

// Supports swapping one asset for another using an external swap router.
// The swap operation is subject to a swap fee and collateral requirements.
// Ownership Management:

// Allows the vault manager to change the owner address.
// Status and Information:

// Provides external functions to query the current status of the vault, including minted EUROs, maximum mintable amount, collateral value, and a list of assets.
// Modifiers and Error Handling:

// Utilizes modifiers to restrict access to certain functions (onlyOwner, onlyVaultManager).
// Uses error messages and exceptions for better error handling.
// Overall, this smart contract aims to provide a decentralized and secure mechanism for managing collateral, minting stablecoins, and performing various financial operations within the defined rules and ratios.
