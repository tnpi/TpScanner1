//
//  NSObject+JAGSerialize.m
//
//  Created by Ryu Iwasaki
//  Copyright (c) 2014 Ryu Iwasaki. All rights reserved.

#import "STMesh+JAGSerialize.h"



@implementation STMesh (JAGSerialize)

//--------------------------------------------------------------//
#pragma mark  - Serialize
//--------------------------------------------------------------//

- (id)loadDataForKey:(NSString *)key{
    
    NSString *fileName = [self _fileNameWithKey:key];
/*
    NSString *archiveFilePath = [self _archiveFilePathWithDirectoryNameInDocumentsDirectory:[self _directoryName]
                                                                                   fileName:fileName];
*/
    id data = [NSKeyedUnarchiver unarchiveObjectWithFile:@"test.dat"];
    
    if (data) {
        
        return data;
    } else {
        
        return nil;
        
    }
    
}

- (void)loadDataForKey:(NSString *)key completionBlock:(void(^)(id dataObject))completion{
    
    __block NSObject *weakSelf = self;
    
    [[[NSOperationQueue alloc]init] addOperationWithBlock:^{
        
//tanaka        id dataObject = [weakSelf loadDataForKey:key];
        
//tanaka        completion(dataObject);
        
    }];
}




- (BOOL)saveWithData:(id<NSCoding>)data forKey:(NSString *)key{
    
    NSLog(@"saveWithData startX");
    
    NSString *fileName = [self _fileNameWithKey:key];

    NSLog(@"archiveFilePath start");

//    NSString *archiveFilePath = [self _archiveFilePathWithDirectoryNameInDocumentsDirectory:[self _directoryName]                                                                                   fileName:fileName];
    
    NSLog(@"NSKeyedArchiver archiveRootObject start");
    
    if ( [NSKeyedArchiver archiveRootObject:data toFile:@"test.dat"] ) {
        
        NSLog(@"saveWithData Return Yes");
        return YES;
    } else {
        
        NSLog(@"saveWithData Return No");
        return NO;
    }
    
    NSLog(@"saveWithData endX");

}

- (void)saveWithData:(id<NSCoding>)data forKey:(NSString *)key completionBlock:(void(^)(BOOL success))completion{
    
    __block NSObject *weakSelf = self;
    [[[NSOperationQueue alloc]init] addOperationWithBlock:^{
        
//tanaka        BOOL success = [weakSelf saveWithData:data forKey:key];
        
        //tanaka        completion(success);
    }];
}


- (NSString *)_archiveFilePathWithDirectoryNameInDocumentsDirectory:(NSString *)dirName fileName:(NSString *)fileName{
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirPath = [paths objectAtIndex:0];
    NSString *archiveDirPath = [documentsDirPath stringByAppendingPathComponent:dirName];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    if (![fileManager fileExistsAtPath:archiveDirPath]) {
        
        if ( [fileManager createDirectoryAtPath:archiveDirPath
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&error] ) {
            if (error) {
                
            }
        }
    }
    
    NSString *archiveFilePath = [archiveDirPath stringByAppendingPathComponent:fileName];
    
    return archiveFilePath;
}

- (NSString *)_fileNameWithKey:(NSString *)key{
    
    NSLog(@"_fileNameWithKey start");
    
    NSString *fileName = [NSString stringWithFormat:@".%@-%@.dat",NSStringFromClass([self class]),key];

    NSLog(@"_fileNameWithKey end");
    
    return fileName;
}

- (NSString *)_directoryName{
    
    NSString *dirName = [[NSString alloc]initWithFormat:@".%@",NSStringFromClass([self class])];
    
    return dirName;
}


@end
