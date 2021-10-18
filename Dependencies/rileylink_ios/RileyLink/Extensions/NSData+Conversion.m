//
//  NSData+Conversion.m
//  GlucoseLink
//
//  Created by Pete Schwamb on 8/5/14.
//  Copyright (c) 2014 Pete Schwamb. All rights reserved.
//

#import "NSData+Conversion.h"

@implementation NSData (Conversion)

- (NSString *)hexadecimalString {
    /* Returns hexadecimal string of NSData. Empty string if data is empty.   */
    
    const unsigned char *dataBuffer = (const unsigned char *)self.bytes;
    
    if (!dataBuffer)
        return [NSString string];
    
    NSUInteger          dataLength  = self.length;
    NSMutableString     *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
    
    for (int i = 0; i < dataLength; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02lx", (unsigned long)dataBuffer[i]]];
    
    return [NSString stringWithString:hexString];
}

+ (NSData*)dataWithHexadecimalString: (NSString*)hexStr
{
    NSMutableData *data = [[NSMutableData alloc] init];
    unsigned char whole_byte;
    char byte_chars[3] = {'\0','\0','\0'};
    for (int i = 0; i < (hexStr.length / 2); i++) {
        byte_chars[0] = [hexStr characterAtIndex:i*2];
        byte_chars[1] = [hexStr characterAtIndex:i*2+1];
        whole_byte = strtol(byte_chars, NULL, 16);
        [data appendBytes:&whole_byte length:1];
    }
    return data;
}

@end
