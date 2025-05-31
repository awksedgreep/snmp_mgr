# SNMP Protocol RFC Reference

This document contains essential RFC references and key protocol details for SNMP implementation work.

## Core SNMP RFCs

### RFC 1157 - SNMPv1 Specification
**URL**: https://www.rfc-editor.org/rfc/rfc1157  
**Title**: The Simple Network Management Protocol (SNMP)  
**Key Content**:
- SNMPv1 PDU definitions and structure
- Basic GET, GETNEXT, SET, RESPONSE, TRAP operations
- ASN.1 encoding for SNMPv1
- Error codes and handling

### RFC 1905 - SNMPv2c Protocol Operations  
**URL**: https://www.rfc-editor.org/rfc/rfc1905  
**Title**: Protocol Operations for Version 2 of the Simple Network Management Protocol (SNMPv2)  
**Key Content**:
- **GETBULK PDU definition** (Section 4.2.3)
- SNMPv2c PDU tag assignments
- Enhanced error handling
- Exception values (noSuchObject, noSuchInstance, endOfMibView)

### RFC 3416 - SNMP Protocol Operations (Updated)
**URL**: https://www.rfc-editor.org/rfc/rfc3416  
**Title**: Version 2 of the Protocol Operations for the Simple Network Management Protocol (SNMP)  
**Key Content**:
- Updated GETBULK specification
- Protocol version compliance requirements
- Enhanced error definitions

### X.690 - ASN.1 BER Encoding Rules
**URL**: https://en.wikipedia.org/wiki/X.690#BER_encoding  
**Title**: ASN.1 Basic Encoding Rules (BER)  
**Key Content**:
- **Length encoding rules** (short form vs long form)
- Tag-Length-Value (TLV) structure
- Integer encoding in two's complement
- SEQUENCE and primitive type encoding

## Critical Protocol Details

### PDU Tag Assignments
```
0xA0 (160) = GetRequest
0xA1 (161) = GetNextRequest  
0xA2 (162) = GetResponse
0xA3 (163) = SetRequest
0xA4 (164) = Trap (SNMPv1)
0xA5 (165) = GetBulkRequest (SNMPv2c only)
0xA6 (166) = InformRequest (SNMPv2c)
0xA7 (167) = SNMPv2-Trap
0xA8 (168) = Report (SNMPv3)
```

### PDU Field Structures

#### Standard PDU (GET, GETNEXT, SET, RESPONSE)
```
PDU ::= SEQUENCE {
    request-id      INTEGER,
    error-status    INTEGER,
    error-index     INTEGER,
    variable-bindings VarBindList
}
```

#### GETBULK PDU (SNMPv2c only) 
```
BulkPDU ::= SEQUENCE {
    request-id          INTEGER,
    non-repeaters       INTEGER,
    max-repetitions     INTEGER,
    variable-bindings   VarBindList
}
```

### BER Length Encoding

#### Short Form (length < 128)
```
Length: 0-127
Encoding: Single byte with bit 7 = 0
Example: Length 42 → 0x2A
```

#### Long Form (length ≥ 128)
```
First byte: 0x80 + number of length bytes
Following bytes: Actual length in big-endian

Examples:
- Length 200 → 0x81 0xC8 (1 byte for length)
- Length 1000 → 0x82 0x03 0xE8 (2 bytes for length)
- Length 100000 → 0x83 0x01 0x86 0xA0 (3 bytes for length)
```

### SNMP Error Codes
```
0 = noError
1 = tooBig
2 = noSuchName
3 = badValue
4 = readOnly
5 = genErr
```

### SNMPv2c Exception Values
```
0x80 = noSuchObject
0x81 = noSuchInstance
0x82 = endOfMibView
```

## Implementation Notes

### Version Compatibility
- **SNMPv1**: Supports GET, GETNEXT, SET, RESPONSE, TRAP
- **SNMPv2c**: Adds GETBULK, InformRequest, enhanced error handling
- **GETBULK**: Only valid in SNMPv2c and later, must reject in SNMPv1

### BER Decoder Requirements
- Must handle both short and long form length encoding
- Must validate length field consistency with actual content
- Must properly decode multi-byte length fields in big-endian format

### GETBULK Parameter Validation
- `non-repeaters`: Number of variables that are not repeated
- `max-repetitions`: Maximum number of iterations for remaining variables
- Both must be non-negative integers
- Typical values: non-repeaters=0, max-repetitions=10-100

## Common Implementation Issues

1. **Large PDU Decoding**: Must implement long-form BER length parsing
2. **GETBULK Recognition**: Must handle tag 0xA5 and different field structure  
3. **Version Compliance**: GETBULK only valid in SNMPv2c, must reject in SNMPv1
4. **Length Validation**: Encoded length must match actual content length
5. **Error Handling**: Different error codes and exception values between versions

## Testing Requirements

- Test BER length encoding for messages >127 bytes
- Validate GETBULK parameter preservation through encode/decode cycle
- Verify version-specific PDU type restrictions
- Test error handling for malformed length encoding
- Validate large message handling (1000+ bytes)