// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

interface IERC20{
    function mint(address to, uint256 amount) external; 
}

contract BloodD is ERC721, AccessControl{

    using Strings for uint256;
    address public owner;
    uint256 public totalBloodDonatedInUnits;
    uint256 public donorIdCounter = 1;
    uint256 public appIdCounter = 1;

    address constant OPOS = 0x870CF0dEDD140db8aD6507611D317eF7fBbe0721 ;
    address constant ONEG = ;
    address constant APOS = ;
    address constant ANEG = ;
    address constant BPOS = ;
    address constant BNEG = ;
    address constant ABPOS = ;
    address constant ABNEG = ;

    // enum BloodGroup {
    //     A+, A-, B+, B-, O+, O-, AB+, AB-
    // }

    enum Status {
        ApplicationSubmitted, 
        ApplicationValidating, ApplicationApproved, ApplicationRejected,
        PhysicalVerificationApproved, PhysicalVerificationFailed,
        OngoingScreeningTest, ScreeningTestFailed, ScreeningTestApprovedAndMovedToStorage
    }    

    struct DonorData{
        bytes32 _donorDataHash;
        uint256 _enrolledTimestamp;
        string _bloodGroup;
        uint256 _totalBloodDonatedUnits;
        address _walletAddress;
        bool _isVerified;
    }
    mapping(uint256 => DonorData) public donorId2Data;
    mapping(bytes32 => uint256) public verifiedDataHash2Id;
    mapping(bytes32 => uint256) public AllDataHash2Id;
    mapping(address => uint256) public address2DonorID;

    struct Application{
        uint256 _donorId;
        string _formURL;
        string _bloodGroup;
        uint256 _appliedTime;
        uint256 _collectionTime;
        string _collectionDate;
        uint256 _closedTime;
        uint256 _bloodDonated;
        Status _status;
    }
    mapping(uint256 => Application) public appId2Data;
    mapping(uint256=>uint256) public donorId2activeAppId;


    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");
    bytes32 public constant PHYSICAL_VERIFIER_ROLE = keccak256("PHYSICAL_VERIFIER_ROLE");
    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");
    bytes32 public constant SCREENER_ROLE = keccak256("SCREENER_ROLE");

    event DonorEnrolled(bytes32 _donorDataHash, string _bloodGroup, address wallet);
    event AppliedForDonation(uint256 _donorId, string _formURL, uint256 appId);
    event ApplicationValidated(uint256 _appId, bool _status);
    event validatedPhysicalUserData(uint256 _appId, bool _status);
    event BloodSampleCollected(uint256 _appId, uint256 _bloodCollectedInUnits, string _date);

    constructor() ERC721("Blood-D-NFT", "BDNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(APPROVER_ROLE, msg.sender);
        _grantRole(PHYSICAL_VERIFIER_ROLE, msg.sender);
        _grantRole(COLLECTOR_ROLE, msg.sender);
        _grantRole(SCREENER_ROLE, msg.sender);
        owner = msg.sender;

    }

    function getDonorIdFromAddress(address _address) external view returns(uint256){
        return address2DonorID[_address];
    }

    function enrollDonor(bytes32  _donorDataHash, string memory _bloodGroup, address wallet) external returns (uint256){
        require(verifiedDataHash2Id[_donorDataHash] == 0, "Sorry, you have already enrolled");
        uint256 donorId = donorIdCounter;

        DonorData memory donorData = DonorData(_donorDataHash, block.timestamp, _bloodGroup, 0, wallet, false);
        donorId2Data[donorId] = donorData;

        AllDataHash2Id[_donorDataHash] = donorId ;
        address2DonorID[wallet] = donorId;
        
        donorIdCounter++;

        emit DonorEnrolled(_donorDataHash, _bloodGroup, wallet);
        return donorId;
    }

    function applyforBloodDonation(uint256 _donorId, string calldata _formURL) external returns (uint256){
        require(donorId2Data[_donorId]._donorDataHash != 0, "Please Enroll before applying!");
        require(donorId2activeAppId[_donorId] == 0, "Application already in progress");
        require(msg.sender == donorId2Data[_donorId]._walletAddress || msg.sender == owner, "Unauthorized access");

        string memory _bloodGroup = donorId2Data[_donorId]._bloodGroup;
        uint256 appId = appIdCounter;

        Application memory app = Application(_donorId, _formURL, _bloodGroup, block.timestamp, 0, '00-00-0000', 0, 0, Status.ApplicationSubmitted);
        appId2Data[appId] = app;
        donorId2activeAppId[_donorId] = appId;

        appIdCounter++;

        emit AppliedForDonation(_donorId, _formURL, appId);
        return appId;
    }


    // ----Approver----: 

    // Application form Approval
    function validateApplication(uint256 _appId, bool _status) external onlyRole(APPROVER_ROLE){
        require(appId2Data[_appId]._status == Status.ApplicationSubmitted, "Invalid Application Id");

        if (_status) 
            appId2Data[_appId]._status = Status.ApplicationApproved;
        else 
            appId2Data[_appId]._status = Status.ApplicationRejected;

        emit ApplicationValidated(_appId, _status);
    }


    // ----Physical Verifer----:

    // User Physical Data Verification at blood bank 
    function validateHashOfUser(uint256 _appId, bytes32 _physicalHash) external view onlyRole(PHYSICAL_VERIFIER_ROLE) returns(bool){
        require(appId2Data[_appId]._donorId != 0 , "Invalid Application Id");
        uint256 donorId = appId2Data[_appId]._donorId;
        bytes32 storedhash = donorId2Data[donorId]._donorDataHash ;
        if (storedhash == _physicalHash)
            return true;
        return false;
    }

    // Verifier calls this function , lastly
    function validatePhysicalUserData(uint256 _appId, bool _status ) external onlyRole(PHYSICAL_VERIFIER_ROLE){
        require(appId2Data[_appId]._status == Status.ApplicationApproved, "Invalid Application Id");

        if (_status) 
            appId2Data[_appId]._status = Status.PhysicalVerificationApproved;
        else 
            appId2Data[_appId]._status = Status.PhysicalVerificationFailed;

        uint256 donorId = appId2Data[_appId]._donorId;
        bytes32 storedhash = donorId2Data[donorId]._donorDataHash ;
        if (verifiedDataHash2Id[storedhash] == 0)
            verifiedDataHash2Id[storedhash] = AllDataHash2Id[storedhash];

        emit validatedPhysicalUserData(_appId, _status);
    }


    // ----Collector----:

    // collectBloodSample
    function collectBloodSample(uint256 _appId, uint256 _bloodDonatedInUnits, string calldata _date) external onlyRole(COLLECTOR_ROLE){
        require(appId2Data[_appId]._status == Status.PhysicalVerificationApproved, "Invalid Application Id");
        require(_bloodDonatedInUnits > 0, "Invalid Amount passed");

        donorId2Data[ appId2Data[_appId]._donorId ]._totalBloodDonatedUnits += _bloodDonatedInUnits;
        totalBloodDonatedInUnits += _bloodDonatedInUnits;

        appId2Data[_appId]._bloodDonated = _bloodDonatedInUnits;
        appId2Data[_appId]._collectionTime = block.timestamp;
        appId2Data[_appId]._collectionDate = _date;

        appId2Data[_appId]._status = Status.OngoingScreeningTest;

        emit BloodSampleCollected(_appId, _bloodDonatedInUnits, _date);
    }


    // ----Screener----: 

    // Screening Test results
    function validateScreeningTest(uint256 _appId, bool _status) external onlyRole(COLLECTOR_ROLE){
        require(appId2Data[_appId]._status == Status.OngoingScreeningTest, "Invalid Application Id");

        if (_status){ 
            appId2Data[_appId]._status = Status.ScreeningTestApprovedAndMovedToStorage;
            uint256 donorId = appId2Data[_appId]._donorId;
            donorId2activeAppId[donorId] = 0;

            address mintTo = donorId2Data[ appId2Data[_appId]._donorId ]._walletAddress;
            _mint(mintTo, _appId);
            
            uint256 units = appId2Data[_appId]._bloodDonated;
            bytes32 group = keccak256(bytes(appId2Data[_appId]._bloodGroup));
            if (group == keccak256(bytes("O +ve")))  IERC20(OPOS).mint(mintTo, units);
            if (group == keccak256(bytes("O -ve")))  IERC20(ONEG).mint(mintTo, units);
            if (group == keccak256(bytes("A +ve")))  IERC20(APOS).mint(mintTo, units);
            if (group == keccak256(bytes("A -ve")))  IERC20(ANEG).mint(mintTo, units);
            if (group == keccak256(bytes("B +ve")))  IERC20(BPOS).mint(mintTo, units);
            if (group == keccak256(bytes("B -ve")))  IERC20(BNEG).mint(mintTo, units);
            if (group == keccak256(bytes("AB +ve")))  IERC20(ABPOS).mint(mintTo, units);
            if (group == keccak256(bytes("AB -ve")))  IERC20(ABNEG).mint(mintTo, units);
            
        }
        else 
            appId2Data[_appId]._status = Status.ScreeningTestFailed;

        appId2Data[_appId]._closedTime = block.timestamp;
    }

     // Overrides required
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool){
        return super.supportsInterface(interfaceId);
    }

    function getDonorBaseSVG(uint256 appId) internal view returns(string memory donorSVGBase){
        donorSVGBase =  string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" style="background:#ffff" width="300" height="300">',
            '<rect id="header" x="0" y="0" width="350" height="69" opacity="90%" fill="rgba(63,0,16,0.938)"/>',
            '<text id="BloodD Header" x="68" y="30"  fill="#ffd6d6" style="font: 20px Zapfino;font-size:13">Blood - D - NFT</text>',
            '<text id="OperationId" x="35" y="63" fill="#fecfcf" style="font: 20px Copperplate ;font-size:20"> Donor Application #', appId.toString() ,'</text>',
            '<path id="plus" fill="#ee9191" stroke="#ffffff" stroke-width="3"  d="M 2 168 h 25 v -25 h 30 v 25 h 25 v 25 h -25 v 25 h -30 v -25 h-25 z" />',
            '<g><rect id="canvas" x="0" y="71" width="140.8" height="100%" opacity="85%" fill="#ec474d"></rect> <rect id="canvas" x="141" y="71" width="100%" height="100%" opacity="85%" fill="#f3adad"></rect> <animate attributeName="opacity" dur="5s"  values="0.45; 0.55; 0.70; 0.85; 1; 0.85; 0.70; 0.55; 0.45" repeatCount="indefinite" /></g>',
            '<path id="Donor Id Border"  stroke="#000000" stroke-width="3" opacity="90%" d="M 127 90 v 30 h160 v -30 z" fill="#ffffff"/> '
            '<text id="Donor Id" x="38" y="110" style="font-family:Monospace;font-size:15">Donor Id: </text>',
            '<text id="Id" x="135" y="110" style="font-family:Monospace;font-size:15">',appId2Data[appId]._donorId.toString(),'</text>'
        ));
    }

    // Onchain NFT logic
    function generateSVG(uint256 appId) public virtual view returns (string memory svg) {

        svg =  string(abi.encodePacked(
            
            getDonorBaseSVG(appId),

            '<path id="Date Border"  stroke="#000000" stroke-width="3" opacity="90%" d="M 127 140 v 30 h160 v -30 z" fill="#ffffff"/> ',
            '<text id="Date1" x="73" y="160" style="font-family:Monospace;font-size:15">Date: </text>'
            '<text id="Date2" x="135" y="160" style="font-family:Monospace;font-size:15">',appId2Data[appId]._collectionDate,'</text>'

            '<path id="Class"  stroke="#000000" stroke-width="3" opacity="90%" d="M 127 190 v 30 h160 v -30 z" fill="#ffffff"/>',
            '<text id="Class1" x="64" y="210" style="font-family:Monospace;font-size:15">Group: </text>'
            '<text id="Class2" x="135" y="210" style="font-family:Monospace;font-size:15">',appId2Data[appId]._bloodGroup,'</text>'

            '<path id="Units Border"  stroke="#000000" stroke-width="3" opacity="90%" d="M 127 240 v 30 h160 v -30 z" fill="#ffffff"/>'
            '<text id="Units1" x="65" y="260" style="font-family:Monospace;font-size:15">Units: </text>'
            '<text id="Units2" x="27" y="275" style="font-family:Monospace;font-size:12">(350ml/Unit)</text>'
            '<text id="Units3" x="135" y="260" style="font-family:Monospace;font-size:15">',appId2Data[appId]._bloodDonated.toString(),'</text></svg>'
        ));

        return svg ;
    }

    function getAttributes(uint256 appId) internal virtual view returns(string memory attr){
        string memory group = appId2Data[appId]._bloodGroup;
        string memory units = appId2Data[appId]._bloodDonated.toString();
        string memory time = appId2Data[appId]._collectionTime.toString();

        attr = string(abi.encodePacked( 
                        '{"trait_type":"Blood Group", "value":"',group,'"},',
                        '{"trait_type":"Units", "value":"',units,'"},'
                        '{"display_type": "date", "trait_type": "DonatedOn", ', '"value": "',time,'"}'
                    )
        );
    }  
    

    function generateFinalMetaJson(uint256 appId) internal view returns (string memory){
        string memory nftName = string(abi.encodePacked("Blood-D-NFT #", appId.toString())) ;
        string memory finalSvg = generateSVG(appId);
        string memory attr = getAttributes(appId);

        // Get all the JSON metadata in place and base64 encode it.
        string memory json = Base64.encode(
            bytes(
                string(abi.encodePacked(
                        // set the title of minted NFT.
                        '{"name": "',nftName,'",',
                        ' "description": "On-Chain Blood-D-NFTs !",',
                        ' "attributes": [',attr,'],',
                        ' "image": "data:image/svg+xml;base64,',
                        //add data:image/svg+xml;base64 and then append our base64 encode our svg.
                        Base64.encode(bytes(finalSvg)),
                        '"}'
                    )
                )
            )
        );

        // prepend data:application/json;base64, to our data.
        string memory finalTokenUri = string(
            abi.encodePacked("data:application/json;base64,", json)
        );
        return finalTokenUri;
    }  

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory){
        return generateFinalMetaJson(tokenId);
    }

} 