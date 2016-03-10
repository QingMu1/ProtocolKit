// The MIT License (MIT)
//
// Copyright (c) 2015-2016 forkingdog ( https://github.com/forkingdog )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// For a magic reserved keyword color, use @defs(your_protocol_name)
#define defs _pk_extension

/*
    @defs(Forkable)
->  @_pk_extension(Forkable)
->  @_pk_extension_imp(Forkable, _pk_get_container_class(Forkable))
->  @_pk_extension_imp(Forkable, _pk_get_container_class_imp(Forkable, 0))
->	@_pk_extension_imp(Forkable, _pk_get_container_class_imp_concat(__PKContainer_, Forkable, 0))
->	@_pk_extension_imp(Forkable, __PKContainer_Forkable_0)
->
 @protocol Forkable;
 @interface __PKContainer_Forkable_0 : NSObject <Forkable> @end
 @implementation __PKContainer_Forkable_1
 + (void)load {
    _pk_extension_load(@protocol(Forkable), __PKContainer_Forkable_1.class);
 }
 
 
 注：__COUNTER__ 是一个编译器扩展，将被替换为一个整型常量,初始值为0，编译单元内每出现一次出现该宏,便它的替换值将会加1。
 */

// Interface
#define _pk_extension($protocol) _pk_extension_imp($protocol, _pk_get_container_class($protocol))

// Implementation
#define _pk_extension_imp($protocol, $container_class) \
    protocol $protocol; \
    @interface $container_class : NSObject <$protocol> @end \
    @implementation $container_class \
    + (void)load { \
        _pk_extension_load(@protocol($protocol), $container_class.class); \
    } \

// Get container class name by counter
#define _pk_get_container_class($protocol) _pk_get_container_class_imp($protocol, __COUNTER__)
#define _pk_get_container_class_imp($protocol, $counter) _pk_get_container_class_imp_concat(__PKContainer_, $protocol, $counter)
#define _pk_get_container_class_imp_concat($a, $b, $c) $a ## $b ## _ ## $c

void _pk_extension_load(Protocol *protocol, Class containerClass);

