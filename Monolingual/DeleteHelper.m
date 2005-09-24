//
//  DeleteHelper.m
//  Monolingual
//
//  Created by Ingmar Stein on Tue Mar 23 2004.
//  Copyright (c) 2004 Ingmar Stein. All rights reserved.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

#import "DeleteHelper.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

static Boolean shouldExit(void)
{
	fd_set fdset;
	struct timeval timeout = {0, 0};
	
	FD_ZERO(&fdset);
	FD_SET(0, &fdset);
	return select(1, &fdset, NULL, NULL, &timeout) == 1;
}

@implementation DeleteHelper
CFSetRef   directories;
CFArrayRef roots;
CFArrayRef excludes;
CFArrayRef files;
BOOL       trash;

- (id) initWithDirectories:(CFSetRef)dirs roots:(CFArrayRef)r excludes:(CFArrayRef)e files:(CFArrayRef)f moveToTrash: (BOOL)t
{
	if( (self = [super init]) ) {
		directories = dirs;
		roots = r;
		excludes = e;
		files = f;
		trash = t;
	}
	return self;
}

- (void) dealloc
{
	CFRelease(files);
	CFRelease(roots);
	CFRelease(directories);
	[super dealloc];
}

- (void) fileManager:(NSFileManager *)manager willProcessPath:(NSString *)path
{
#pragma unused(manager)
	struct stat st;
	const char *filename = [path fileSystemRepresentation];
	if( stat(filename, &st) != -1 ) {
		printf( "%s%c%llu%c", filename, '\0', st.st_size, '\0' );
		fflush( stdout );
	}
}

- (BOOL) fileManager:(NSFileManager *)manager shouldProceedAfterError:(NSDictionary *)errorInfo
{
#pragma unused(manager,errorInfo)
	return TRUE;
}

- (void) removeFile:(NSString *)path
{
	if( trash ) {
		int tag;
		NSString *parent = [path stringByDeletingLastPathComponent];
		NSString *file = [path lastPathComponent];
		CFArrayRef filesToRecycle = CFArrayCreate(kCFAllocatorDefault, (const void **)&file, 1, &kCFTypeArrayCallBacks);
		NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
		[workspace performFileOperation:NSWorkspaceRecycleOperation
								 source:parent
							destination:@""
								  files:(NSArray *)filesToRecycle
									tag:&tag];
		CFRelease(filesToRecycle);
		printf( "%s%c%llu%c", [path fileSystemRepresentation], '\0', 0ULL, '\0' );
		fflush( stdout );
	} else
		[[NSFileManager defaultManager] removeFileAtPath:path handler:self];
}

- (void) removeDirectories
{
	NSString *root;
	NSString *file;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSFileManager *fileManager = [NSFileManager defaultManager];

	// delete regular files
	for (CFIndex i=0, count=CFArrayGetCount(files); i<count; ++i) {
		if (shouldExit())
			break;
		file = (NSString *)CFArrayGetValueAtIndex(files, i);
		[self removeFile:file];
	}

	// recursively delete directories
	for (CFIndex i=0, count=CFArrayGetCount(roots); i<count; ++i) {
		if (shouldExit())
			break;
		root = (NSString *)CFArrayGetValueAtIndex(roots, i);
		NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:root];
		while( 1 ) {
			NSAutoreleasePool *pool2 = [[NSAutoreleasePool alloc] init];
			file = [dirEnum nextObject];
			if( !file || shouldExit() ) {
				[pool2 release];
				break;
			}
			if( [[[dirEnum fileAttributes] fileType] isEqualToString:NSFileTypeDirectory] ) {
				BOOL process = TRUE;
				CFStringRef path = (CFStringRef)[root stringByAppendingPathComponent:file];
				for (CFIndex j=0, exclude_count=CFArrayGetCount(excludes); j<exclude_count; ++j) {
					CFStringRef exclude = CFArrayGetValueAtIndex(excludes, j);
					if( CFStringHasPrefix(path, exclude) ) {
						process = FALSE;
						[dirEnum skipDescendents];
						break;
					}
				}
				if( process && CFSetContainsValue(directories, [file lastPathComponent]) ) {
					[dirEnum skipDescendents];
					[self removeFile:(NSString *)path];
				}
			}
			[pool2 release];
		}
	}

	[pool release];
}

@end
