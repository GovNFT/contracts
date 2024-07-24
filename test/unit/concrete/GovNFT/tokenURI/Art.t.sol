// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract ArtTest is BaseTest, ArtProxy {
    address public OP = 0x4200000000000000000000000000000000000042;
    address public govNFTAddr = 0x522B3294E6d06aA25Ad0f1B8891242E335D3B459; //arbitrary address

    function test_NameAndDescription() public {
        ConstructTokenURIParams memory params = ConstructTokenURIParams({
            lockTokenSymbol: "OP",
            lockTokenDecimals: 18,
            govNFT: govNFTAddr,
            govNFTSymbol: "GOVNFT",
            tokenId: 1223,
            lockToken: OP,
            initialDeposit: 43200e18,
            vestingAmount: 10000e18,
            lockStart: 12345,
            lockEnd: 67890,
            cliff: 123
        });
        string memory nameAndDescription = constructTokenURI(params);
        string memory expectedNameAndDescription = string(
            abi.encodePacked('"name":"', generateName(), '", "description":"', generateDescription(), '"')
        );
        assertEq(nameAndDescription, expectedNameAndDescription);
    }

    function test_generateSVG() public {
        //mock call to totalVested 42300e18/4
        vm.mockCall(govNFTAddr, abi.encodeWithSelector(IGovNFT.totalVested.selector, 1223), abi.encode(42300e18 / 4));

        string memory svg = generateSVG({
            _govNFT: govNFTAddr,
            _tokenId: 1223,
            _totalLockAmount: 42300e18,
            _lockTokenSymbol: "OP",
            _lockTokenDecimals: 18,
            _totalLockTime: 730 days //2 years
        });

        string memory expectedSVG = generateSVG();
        assertEq(svg, expectedSVG);
    }

    function test_convertToDecimals() public {
        string memory text = convertToDecimals(43_200e18, 18, 0);
        assertEq(text, "43,200");

        text = convertToDecimals(43_200e18, 18, 2);
        assertEq(text, "43,200.00");

        text = convertToDecimals(100_043_200e18, 18, 2);
        assertEq(text, "100,043,200.00");
    }

    function test_convertToTime() public {
        string memory text = convertToTime(YEAR);
        assertEq(text, "1 year");

        text = convertToTime(YEAR * 2);
        assertEq(text, "2 years");

        text = convertToTime(MONTH);
        assertEq(text, "1 month");

        text = convertToTime(MONTH * 2);
        assertEq(text, "2 months");

        text = convertToTime(YEAR + MONTH * 2);
        assertEq(text, "1 year and 2 months");

        text = convertToTime(YEAR * 2 + MONTH * 5);
        assertEq(text, "2 years and 5 months");

        text = convertToTime(1 days);
        assertEq(text, "1 day");

        text = convertToTime(MONTH * 5 + 28 days);
        assertEq(text, "5 months");

        text = convertToTime(YEAR + MONTH * 5 + 28 days);
        assertEq(text, "1 year and 5 months");
    }

    function generateName() internal pure returns (string memory name) {
        name = "GOVNFT with vesting OP tokens";
    }

    function generateDescription() internal pure returns (string memory description) {
        description = string(
            abi.encodePacked(
                "The owner of this NFT can claim airdrops, delegate voting power, transfer and split the locked amount into new NFTs.\\n",
                "\\nGovNFT Address: 0x522b3294e6d06aa25ad0f1b8891242e335d3b459",
                "\\nSymbol: GOVNFT",
                "\\nToken ID: 1223",
                "\\nLocked Token: 0x4200000000000000000000000000000000000042",
                "\\nLocked Amount: 43,200",
                "\\nVesting Amount: 10,000",
                "\\nVesting Start Date: 12345",
                "\\nVesting End Date: 67890",
                "\\nCliff: 123",
                "\\n\\n",
                unicode"⚠️ DISCLAIMER: Due diligence is imperative when assessing this NFT. Make sure token addresses match the expected tokens, as token symbols may be imitated."
            )
        );
    }

    function generateSVG() internal pure returns (string memory svg) {
        svg = string(abi.encodePacked(generateSVG1(), generateSVG2(), generateSVG3(), generateSVG4()));
    }

    function generateSVG1() internal pure returns (string memory svgPart1) {
        svgPart1 = string(
            abi.encodePacked(
                '<svg width="800" height="800" viewBox="0 0 800 800" fill="none" xmlns="http://www.w3.org/2000/svg">',
                '<g clip-path="url(#clip0_207_365)">',
                '<rect width="800" height="800" fill="#171F2D"/>',
                '<rect width="800" height="800" fill="#252525"/>'
            )
        );
    }

    function generateSVG2() internal pure returns (string memory svgPart2) {
        svgPart2 = string(
            abi.encodePacked(
                '<path d="M283.681 108.458V69.9374H270.569V64.542H302.502V69.9374H289.39V108.458H283.681Z" fill="white"/>',
                '<path d="M240.78 108.458V64.542H265.749V69.6864H246.489V85.5588H265.749V90.7032H246.489V108.458H240.78Z" fill="white"/>',
                '<path d="M199.425 108.458V64.542H205.511L225.273 98.9217V64.542H230.731V108.458H224.708L204.884 74.078V108.458H199.425Z" fill="white"/>',
                '<path d="M154.579 64.542H165.495L174.592 95.5339L183.689 64.542H194.605L179.862 108.458H169.322L154.579 64.542Z" fill="white"/>',
                '<path d="M132.321 109.713C127.553 109.713 123.391 108.667 119.836 106.576C116.281 104.485 113.563 101.682 111.681 98.1691C109.798 94.614 108.857 90.7243 108.857 86.5001C108.857 82.2758 109.798 78.407 111.681 74.8938C113.563 71.3387 116.281 68.5156 119.836 66.4244C123.391 64.3331 127.553 63.2875 132.321 63.2875C137.089 63.2875 141.25 64.3331 144.805 66.4244C148.361 68.5156 151.079 71.3387 152.961 74.8938C154.843 78.407 155.784 82.2758 155.784 86.5001C155.784 90.7243 154.843 94.614 152.961 98.1691C151.079 101.682 148.361 104.485 144.805 106.576C141.25 108.667 137.089 109.713 132.321 109.713ZM132.321 100.616C134.998 100.616 137.298 99.9884 139.222 98.7337C141.188 97.479 142.672 95.7851 143.676 93.652C144.68 91.4772 145.182 89.0932 145.182 86.5001C145.182 83.907 144.68 81.5439 143.676 79.4108C142.672 77.236 141.188 75.5212 139.222 74.2664C137.298 73.0117 134.998 72.3843 132.321 72.3843C129.602 72.3843 127.26 73.0117 125.294 74.2664C123.37 75.5212 121.907 77.236 120.903 79.4108C119.899 81.5439 119.418 83.907 119.46 86.5001C119.418 89.0932 119.899 91.4772 120.903 93.652C121.907 95.7851 123.37 97.479 125.294 98.7337C127.26 99.9884 129.602 100.616 132.321 100.616Z" fill="white"/>',
                '<path d="M105.179 93.0246H101.038C99.9091 98.3363 97.4206 102.456 93.5727 105.384C89.7667 108.27 84.8524 109.713 78.8297 109.713C74.229 109.713 70.172 108.73 66.6588 106.764C63.1455 104.798 60.4269 102.08 58.503 98.6082C56.5791 95.0949 55.6171 91.1634 55.6171 86.8137C55.6171 82.5058 56.5373 78.5743 58.3775 75.0192C60.2596 71.4223 62.9991 68.5783 66.596 66.487C70.1929 64.354 74.459 63.2875 79.3943 63.2875C83.2421 63.2875 86.6926 63.9358 89.7458 65.2323C92.8408 66.487 95.2875 68.2437 97.086 70.5022C98.8844 72.7607 99.9091 75.312 100.16 78.156H89.0557C88.6375 76.2739 87.5709 74.7474 85.8561 73.5763C84.1832 72.4052 82.0501 71.8196 79.457 71.8196C75.1491 71.8196 71.845 73.1789 69.5446 75.8975C67.2861 78.6161 66.1778 82.1503 66.2196 86.5C66.2196 89.2186 66.7424 91.6862 67.788 93.9029C68.8336 96.0778 70.3184 97.7926 72.2423 99.0473C74.2081 100.26 76.4875 100.867 79.0806 100.867C85.2288 100.867 89.0557 98.2527 90.5614 93.0246H82.7193V85.3707H105.179V93.0246Z" fill="white"/>'
            )
        );
    }

    function generateSVG3() internal pure returns (string memory svgPart3) {
        svgPart3 = string(
            abi.encodePacked(
                '<text fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="20" letter-spacing="0em"><tspan x="56" y="152.913">ID #1223</tspan></text>',
                '<path d="M302.502 234L302.502 566L6.46425e-05 566L6.10352e-05 234L302.502 234Z" fill="url(#paint0_linear_207_365)"/>',
                '<rect x="165.498" y="248.499" width="303.004" height="303.004" rx="151.502" fill="#EE2524"/>',
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M302.502 234H634.502V566H302.502V234ZM353.6 285.098V514.902H583.404V285.098H353.6Z" fill="white"/>',
                '<text fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="32" font-weight="bold" letter-spacing="0em"><tspan x="56" y="676.594">42,300.00 OP, in 2 years</tspan></text>',
                '<rect opacity="0.05" x="56" y="700" width="693" height="2" fill="#D9D9D9"/>',
                '<text fill="#F3F4F6" xml:space="preserve" style="white-space: pre" font-family="Arial" font-size="20" letter-spacing="0em"><tspan x="56" y="736.434">Vested 25%</tspan></text>',
                "</g>"
            )
        );
    }

    function generateSVG4() internal pure returns (string memory svgPart4) {
        svgPart4 = string(
            abi.encodePacked(
                "<defs>",
                '<linearGradient id="paint0_linear_207_365" x1="376.976" y1="566" x2="20.1236" y2="566" gradientUnits="userSpaceOnUse">',
                '<stop offset="0.142" stop-color="#474340" stop-opacity="0.5"/>',
                '<stop offset="1" stop-color="#21293A" stop-opacity="0"/>',
                "</linearGradient>",
                '<clipPath id="clip0_207_365">',
                '<rect width="800" height="800" fill="white"/>',
                "</clipPath>",
                "</defs>",
                "</svg>"
            )
        );
    }
}
