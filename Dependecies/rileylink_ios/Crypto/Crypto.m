//
//  Crypto.m
//  RileyLink
//
//  Created by Nate Racklyeft on 9/13/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

#import "Crypto.h"
#import <CommonCrypto/CommonDigest.h>
#import "NSData+Conversion.h"

@implementation NSString (Crypto)

- (NSString *)sha1
{
    NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t outbytes[CC_SHA1_DIGEST_LENGTH];

    CC_SHA1(data.bytes, (CC_LONG)data.length, outbytes);

    NSData *outdata = [[NSData alloc] initWithBytes:outbytes length:CC_SHA1_DIGEST_LENGTH];

    return outdata.hexadecimalString;
}

@end
