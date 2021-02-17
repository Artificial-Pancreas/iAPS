//
//  NSData+Conversion.h
//  GlucoseLink
//
//  Created by Pete Schwamb on 8/5/14.
//  Copyright (c) 2014 Pete Schwamb. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Conversion)

@property (nonatomic, readonly, copy) NSString *hexadecimalString;
+ (NSData*)dataWithHexadecimalString: (NSString*)hexStr;

@end
