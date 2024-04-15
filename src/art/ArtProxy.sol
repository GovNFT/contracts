// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {IArtProxy} from "../interfaces/IArtProxy.sol";
import {IGovNFT} from "../interfaces/IGovNFT.sol";

/// @title GovNFT Art
/// @notice Art associated with GovNFT
contract ArtProxy is IArtProxy {
    using Strings for uint256;

    /// @inheritdoc IArtProxy
    function tokenURI(uint256 _tokenId) external view returns (string memory output) {
        address govNFT = msg.sender;
        IGovNFT.Lock memory lock = IGovNFT(govNFT).locks(_tokenId);
        ConstructTokenURIParams memory params = ConstructTokenURIParams({
            lockTokenSymbol: IERC20Metadata(lock.token).symbol(),
            lockTokenDecimals: IERC20Metadata(lock.token).decimals(),
            govNFT: govNFT,
            govNFTSymbol: IERC721Metadata(govNFT).symbol(),
            tokenId: _tokenId,
            lockToken: lock.token,
            initialDeposit: lock.initialDeposit,
            vestingAmount: lock.totalLocked,
            lockStart: lock.start,
            lockEnd: lock.end,
            cliff: lock.cliffLength
        });

        string memory image = Base64.encode(
            bytes(
                generateSVG({
                    _govNFT: govNFT,
                    _tokenId: _tokenId,
                    _totalLockAmount: params.initialDeposit,
                    _lockTokenSymbol: params.lockTokenSymbol,
                    _lockTokenDecimals: params.lockTokenDecimals,
                    _totalLockTime: params.lockEnd - params.lockStart
                })
            )
        );

        string memory nameAndDescription = constructTokenURI(params);

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                "{",
                                nameAndDescription,
                                ', "image": "',
                                "data:image/svg+xml;base64,",
                                image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    /// @dev helper function for NFT Art
    function generateSVG(
        address _govNFT,
        uint256 _tokenId,
        uint256 _totalLockAmount,
        string memory _lockTokenSymbol,
        uint8 _lockTokenDecimals,
        uint256 _totalLockTime
    ) internal view returns (string memory) {
        uint256 amountVestedPercentage = Math.mulDiv(IGovNFT(_govNFT).totalVested(_tokenId), 100, _totalLockAmount);
        return
            string(
                abi.encodePacked(
                    '<svg width="800" height="800" viewBox="0 0 800 800" fill="none" xmlns="http://www.w3.org/2000/svg">',
                    '<g clip-path="url(#clip0_207_365)">',
                    '<rect width="800" height="800" fill="#171F2D"/>',
                    '<rect width="800" height="800" fill="#252525"/>',
                    generateGOVNFTLogo(),
                    generateTopText(_tokenId),
                    generateArt(),
                    generateBottomText(_totalLockAmount, _lockTokenSymbol, _lockTokenDecimals, _totalLockTime),
                    generateBottomLastText(amountVestedPercentage),
                    generateSVGDefs(),
                    "</svg>"
                )
            );
    }

    function constructTokenURI(ConstructTokenURIParams memory _params) internal pure returns (string memory) {
        string memory name = generateName(_params.govNFTSymbol, _params.lockTokenSymbol);

        string memory description = string(
            abi.encodePacked(
                generateGovNFTDescription(_params.govNFT, _params.govNFTSymbol, _params.tokenId),
                generateLockDescription(
                    _params.lockToken,
                    _params.lockTokenDecimals,
                    _params.initialDeposit,
                    _params.vestingAmount,
                    _params.lockStart,
                    _params.lockEnd,
                    _params.cliff
                )
            )
        );

        return string(abi.encodePacked('"name":"', name, '", "description":"', description, '"'));
    }

    function generateName(
        string memory _govNFTSymbol,
        string memory _lockTokenSymbol
    ) private pure returns (string memory) {
        return string(abi.encodePacked(_govNFTSymbol, " with vesting ", _lockTokenSymbol, " tokens"));
    }

    function generateGovNFTDescription(
        address _govNFT,
        string memory _govNFTSymbol,
        uint256 _tokenId
    ) private pure returns (string memory description) {
        description = string(
            abi.encodePacked(
                "The owner of this NFT can claim airdrops, delegate voting power, transfer and split the locked amount into new NFTs.\\n",
                "\\nGovNFT Address: ",
                addressToString(_govNFT),
                "\\nSymbol: ",
                _govNFTSymbol,
                "\\nToken ID: ",
                _tokenId.toString()
            )
        );
    }

    function generateLockDescription(
        address _lockToken,
        uint8 _lockTokenDecimals,
        uint256 _initialDeposit,
        uint256 _vestingAmount,
        uint256 _start,
        uint256 _end,
        uint256 _cliff
    ) private pure returns (string memory description) {
        description = string(
            abi.encodePacked(
                "\\nLocked Token: ",
                addressToString(_lockToken),
                "\\nLocked Amount: ",
                convertToDecimals(_initialDeposit, _lockTokenDecimals, 0),
                "\\nVesting Amount: ",
                convertToDecimals(_vestingAmount, _lockTokenDecimals, 0),
                "\\nVesting Start Date: ",
                _start.toString(),
                "\\nVesting End Date: ",
                _end.toString(),
                "\\nCliff: ",
                _cliff.toString(),
                "\\n\\n",
                unicode"⚠️ DISCLAIMER: Due diligence is imperative when assessing this NFT. Make sure token addresses match the expected tokens, as token symbols may be imitated."
            )
        );
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        return uint256(uint160(_addr)).toHexString(20);
    }

    function generateArt() private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                //Fade left side
                '<path d="M302.502 234L302.502 566L6.46425e-05 566L6.10352e-05 234L302.502 234Z" fill="url(#paint0_linear_207_365)"/>',
                //Red circle
                '<rect x="165.498" y="248.499" width="303.004" height="303.004" rx="151.502" fill="#EE2524"/>',
                //White square
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M302.502 234H634.502V566H302.502V234ZM353.6 285.098V514.902H583.404V285.098H353.6Z" fill="white"/>'
            )
        );
    }

    function generateGOVNFTLogo() private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                //GOVNFT logo
                // Each path represents a part of the GOVNFT logo design
                '<path d="M283.681 108.458V69.9374H270.569V64.542H302.502V69.9374H289.39V108.458H283.681Z" fill="white"/>',
                '<path d="M240.78 108.458V64.542H265.749V69.6864H246.489V85.5588H265.749V90.7032H246.489V108.458H240.78Z" fill="white"/>',
                '<path d="M199.425 108.458V64.542H205.511L225.273 98.9217V64.542H230.731V108.458H224.708L204.884 74.078V108.458H199.425Z" fill="white"/>',
                '<path d="M154.579 64.542H165.495L174.592 95.5339L183.689 64.542H194.605L179.862 108.458H169.322L154.579 64.542Z" fill="white"/>',
                '<path d="M132.321 109.713C127.553 109.713 123.391 108.667 119.836 106.576C116.281 104.485 113.563 101.682 111.681 98.1691C109.798 94.614 108.857 90.7243 108.857 86.5001C108.857 82.2758 109.798 78.407 111.681 74.8938C113.563 71.3387 116.281 68.5156 119.836 66.4244C123.391 64.3331 127.553 63.2875 132.321 63.2875C137.089 63.2875 141.25 64.3331 144.805 66.4244C148.361 68.5156 151.079 71.3387 152.961 74.8938C154.843 78.407 155.784 82.2758 155.784 86.5001C155.784 90.7243 154.843 94.614 152.961 98.1691C151.079 101.682 148.361 104.485 144.805 106.576C141.25 108.667 137.089 109.713 132.321 109.713ZM132.321 100.616C134.998 100.616 137.298 99.9884 139.222 98.7337C141.188 97.479 142.672 95.7851 143.676 93.652C144.68 91.4772 145.182 89.0932 145.182 86.5001C145.182 83.907 144.68 81.5439 143.676 79.4108C142.672 77.236 141.188 75.5212 139.222 74.2664C137.298 73.0117 134.998 72.3843 132.321 72.3843C129.602 72.3843 127.26 73.0117 125.294 74.2664C123.37 75.5212 121.907 77.236 120.903 79.4108C119.899 81.5439 119.418 83.907 119.46 86.5001C119.418 89.0932 119.899 91.4772 120.903 93.652C121.907 95.7851 123.37 97.479 125.294 98.7337C127.26 99.9884 129.602 100.616 132.321 100.616Z" fill="white"/>',
                '<path d="M105.179 93.0246H101.038C99.9091 98.3363 97.4206 102.456 93.5727 105.384C89.7667 108.27 84.8524 109.713 78.8297 109.713C74.229 109.713 70.172 108.73 66.6588 106.764C63.1455 104.798 60.4269 102.08 58.503 98.6082C56.5791 95.0949 55.6171 91.1634 55.6171 86.8137C55.6171 82.5058 56.5373 78.5743 58.3775 75.0192C60.2596 71.4223 62.9991 68.5783 66.596 66.487C70.1929 64.354 74.459 63.2875 79.3943 63.2875C83.2421 63.2875 86.6926 63.9358 89.7458 65.2323C92.8408 66.487 95.2875 68.2437 97.086 70.5022C98.8844 72.7607 99.9091 75.312 100.16 78.156H89.0557C88.6375 76.2739 87.5709 74.7474 85.8561 73.5763C84.1832 72.4052 82.0501 71.8196 79.457 71.8196C75.1491 71.8196 71.845 73.1789 69.5446 75.8975C67.2861 78.6161 66.1778 82.1503 66.2196 86.5C66.2196 89.2186 66.7424 91.6862 67.788 93.9029C68.8336 96.0778 70.3184 97.7926 72.2423 99.0473C74.2081 100.26 76.4875 100.867 79.0806 100.867C85.2288 100.867 89.0557 98.2527 90.5614 93.0246H82.7193V85.3707H105.179V93.0246Z" fill="white"/>'
            )
        );
    }

    function generateTopText(uint256 _tokenId) private pure returns (string memory svg) {
        string memory tokenIdText = string(abi.encodePacked("ID #", _tokenId.toString()));
        svg = string(
            abi.encodePacked(
                '<text fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="20" letter-spacing="0em"><tspan x="56" y="152.913">',
                tokenIdText,
                "</tspan></text>"
            )
        );
    }

    function generateBottomText(
        uint256 _totalLockAmount,
        string memory _lockTokenSymbol,
        uint8 _lockTokenDecimals,
        uint256 _totalLockTime
    ) private pure returns (string memory svg) {
        string memory amountOfTokensAndSymbol = string(
            abi.encodePacked(convertToDecimals(_totalLockAmount, _lockTokenDecimals, 2), " ", _lockTokenSymbol)
        );
        string memory amountOfTime = convertToTime(_totalLockTime);

        svg = string(
            abi.encodePacked(
                '<text fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="32" font-weight="bold" letter-spacing="0em"><tspan x="56" y="676.594">',
                amountOfTokensAndSymbol,
                ", in ",
                amountOfTime,
                "</tspan></text>"
            )
        );
    }

    function generateBottomLastText(uint256 _amountVestedPercentage) private pure returns (string memory svg) {
        string memory amountVestedPercentage = string(
            abi.encodePacked("Vested ", _amountVestedPercentage.toString(), "%")
        );
        svg = string(
            abi.encodePacked(
                '<rect opacity="0.05" x="56" y="700" width="693" height="2" fill="#D9D9D9"/>', // thin grey line separator
                '<text fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="20" letter-spacing="0em"><tspan x="56" y="736.434">',
                amountVestedPercentage,
                "</tspan></text>"
            )
        );
    }

    function convertToDecimals(
        uint256 _amount,
        uint8 _decimals,
        uint8 _decimalsToPrint
    ) internal pure returns (string memory) {
        uint256 divisor = 10 ** _decimals;
        uint256 integerPart = _amount / divisor;
        uint256 fractionalPart = _amount % divisor;

        // trim to desired dp
        if (_decimals > _decimalsToPrint) {
            uint256 adjustedDivisor = 10 ** (_decimals - _decimalsToPrint);
            fractionalPart = adjustedDivisor > 0 ? fractionalPart / adjustedDivisor : fractionalPart;
        }

        // add leading zeroes
        string memory leadingZeros = "";
        uint256 fractionalPartLength = bytes(fractionalPart.toString()).length;
        uint256 zerosToAdd = _decimalsToPrint > fractionalPartLength ? _decimalsToPrint - fractionalPartLength : 0;
        for (uint256 i = 0; i < zerosToAdd; i++) {
            leadingZeros = string(abi.encodePacked("0", leadingZeros));
        }
        string memory integerFormatted = formatIntegerWithCommas(integerPart.toString());
        return
            _decimalsToPrint > 0
                ? string(abi.encodePacked(integerFormatted, ".", leadingZeros, fractionalPart.toString()))
                : string(abi.encodePacked(integerFormatted));
    }

    function formatIntegerWithCommas(string memory _integer) internal pure returns (string memory) {
        bytes memory integerBytes = bytes(_integer);
        uint256 length = integerBytes.length;

        if (length < 4) {
            return _integer;
        }

        uint256 commas = (length - 1) / 3;

        bytes memory integerWithCommas = new bytes(length + commas);
        uint256 idx;

        for (uint256 i = 0; i < length; ++i) {
            integerWithCommas[idx++] = integerBytes[i];

            if ((length - 1 - i) % 3 == 0 && i != length - 1) {
                integerWithCommas[idx++] = bytes1(",");
            }
        }

        return string(integerWithCommas);
    }

    function convertToTime(uint256 _time) internal pure returns (string memory text) {
        uint256 day = 1 days;
        uint256 month = 30 days;
        uint256 year = 365 days;

        if (_time >= year) {
            uint256 numberOfYears = _time / year;
            uint256 numberOfMonths = (_time % year) / month;
            text = string(abi.encodePacked(numberOfYears.toString(), numberOfYears == 1 ? " year" : " years"));
            if (numberOfMonths > 0) {
                text = string(
                    abi.encodePacked(
                        text,
                        " and ",
                        numberOfMonths.toString(),
                        numberOfMonths == 1 ? " month" : " months"
                    )
                );
            }
        } else if (_time >= month) {
            _time = _time / month;
            text = string(abi.encodePacked(_time.toString(), _time == 1 ? " month" : " months"));
        } else {
            _time = _time / day;
            text = string(abi.encodePacked(_time.toString(), _time == 1 ? " day" : " days"));
        }
    }

    function generateSVGDefs() private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                "</g>", // closing initial setup, art and text
                //Definitions for gradients and clip paths
                "<defs>",
                '<linearGradient id="paint0_linear_207_365" x1="376.976" y1="566" x2="20.1236" y2="566" gradientUnits="userSpaceOnUse">',
                '<stop offset="0.142" stop-color="#474340" stop-opacity="0.5"/>',
                '<stop offset="1" stop-color="#21293A" stop-opacity="0"/>',
                "</linearGradient>",
                '<clipPath id="clip0_207_365">',
                '<rect width="800" height="800" fill="white"/>',
                "</clipPath>",
                "</defs>"
            )
        );
    }
}
