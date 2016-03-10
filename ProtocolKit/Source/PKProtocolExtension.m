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
#import "PKProtocolExtension.h"
#import <pthread.h>

typedef struct {
    Protocol *__unsafe_unretained protocol;
    Method *instanceMethods;
    unsigned instanceMethodCount;
    Method *classMethods;
    unsigned classMethodCount;
} PKExtendedProtocol;

// 储存所有的扩展包括类扩展和实例扩展
static PKExtendedProtocol *allExtendedProtocols = NULL;
// 用于互斥锁，保证在执行构造函数时 allExtendedProtocols 已经初始化完成
static pthread_mutex_t protocolsLoadingLock = PTHREAD_MUTEX_INITIALIZER;
static size_t extendedProtcolCount = 0, extendedProtcolCapacity = 0;

// 合并existMethods和appendingMethods，生成一个新的 Method 列表
Method *_pk_extension_create_merged(Method *existMethods, unsigned existMethodCount, Method *appendingMethods, unsigned appendingMethodCount) {
    
    if (existMethodCount == 0) {
        return appendingMethods;
    }
    unsigned mergedMethodCount = existMethodCount + appendingMethodCount;
    Method *mergedMethods = malloc(mergedMethodCount * sizeof(Method));
    memcpy(mergedMethods, existMethods, existMethodCount * sizeof(Method));
    memcpy(mergedMethods + existMethodCount, appendingMethods, appendingMethodCount * sizeof(Method));
    return mergedMethods;
}

// 把当前 containerClass 的所有方法(实例方法&类方法)加入到对应 extendedProtocol 的方法列表里面去
void _pk_extension_merge(PKExtendedProtocol *extendedProtocol, Class containerClass) {
    
//    把 containerClass 里面的所有实例方法加入到 extendedProtocol->instanceMethods 里面
    // Instance methods
    unsigned appendingInstanceMethodCount = 0;
    Method *appendingInstanceMethods = class_copyMethodList(containerClass, &appendingInstanceMethodCount);
    Method *mergedInstanceMethods = _pk_extension_create_merged(extendedProtocol->instanceMethods,
                                                                extendedProtocol->instanceMethodCount,
                                                                appendingInstanceMethods,
                                                                appendingInstanceMethodCount);
    free(extendedProtocol->instanceMethods);
    extendedProtocol->instanceMethods = mergedInstanceMethods;
    extendedProtocol->instanceMethodCount += appendingInstanceMethodCount;
    
//    把 containerClass 里面的所有类方法加入到 extendedProtocol->instanceMethods 里面
    // Class methods
    unsigned appendingClassMethodCount = 0;
    Method *appendingClassMethods = class_copyMethodList(object_getClass(containerClass), &appendingClassMethodCount);
    Method *mergedClassMethods = _pk_extension_create_merged(extendedProtocol->classMethods,
                                                             extendedProtocol->classMethodCount,
                                                             appendingClassMethods,
                                                             appendingClassMethodCount);
    free(extendedProtocol->classMethods);
    extendedProtocol->classMethods = mergedClassMethods;
    extendedProtocol->classMethodCount += appendingClassMethodCount;
}

// 在 load 时执行，早于 main 函数，也早于构造函数
void _pk_extension_load(Protocol *protocol, Class containerClass) {
    
    pthread_mutex_lock(&protocolsLoadingLock);
    
//    动态增加allExtendedProtocols的数组大小，2的次幂来增加其容量
    if (extendedProtcolCount >= extendedProtcolCapacity) {
        size_t newCapacity = 0;
        if (extendedProtcolCapacity == 0) {
            newCapacity = 1;
        } else {
            newCapacity = extendedProtcolCapacity << 1;
        }
//      这里 realloc 会先预判当前指针是否有足够的连续空间，如果有，直接扩大其指向地址，否则才会重新开辟空间，并把当前allExtendedProtocols全部复制过去，同时释放当前空间
        allExtendedProtocols = realloc(allExtendedProtocols, sizeof(*allExtendedProtocols) * newCapacity);
        extendedProtcolCapacity = newCapacity;
    }
    
//    检查 allExtendedProtocols 里面是否已存在这个 protocol ，没有的话就创建一个 PKExtendedProtocol
//    resultIndex 为这个 protocol 在 allExtendedProtocols 中的索引位置
    size_t resultIndex = SIZE_T_MAX;
    for (size_t index = 0; index < extendedProtcolCount; ++index) {
        if (allExtendedProtocols[index].protocol == protocol) {
            resultIndex = index;
            break;
        }
    }
    if (resultIndex == SIZE_T_MAX) {
        allExtendedProtocols[extendedProtcolCount] = (PKExtendedProtocol){
            .protocol = protocol,
            .instanceMethods = NULL,
            .instanceMethodCount = 0,
            .classMethods = NULL,
            .classMethodCount = 0,
        };
        resultIndex = extendedProtcolCount;
        extendedProtcolCount++;
    }
    
    _pk_extension_merge(&(allExtendedProtocols[resultIndex]), containerClass);

    pthread_mutex_unlock(&protocolsLoadingLock);
}

// 把 extendedProtocol 里面的所有方法加入到 targetClass 的方法列表里面去
static void _pk_extension_inject_class(Class targetClass, PKExtendedProtocol extendedProtocol) {
    
//    添加实例方法
    for (unsigned methodIndex = 0; methodIndex < extendedProtocol.instanceMethodCount; ++methodIndex) {
        Method method = extendedProtocol.instanceMethods[methodIndex];
        SEL selector = method_getName(method);
//        如果类本身有实现这个方法，那么就不去覆盖
        if (class_getInstanceMethod(targetClass, selector)) {
            continue;
        }
        
        IMP imp = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);
        class_addMethod(targetClass, selector, imp, types);
    }
    
//    添加类方法
    Class targetMetaClass = object_getClass(targetClass);
    for (unsigned methodIndex = 0; methodIndex < extendedProtocol.classMethodCount; ++methodIndex) {
        Method method = extendedProtocol.classMethods[methodIndex];
        SEL selector = method_getName(method);
//        load 和 initialize 方法不会覆盖，因为实现中重写了 load 方法。所以这里需要排除下
        if (selector == @selector(load) || selector == @selector(initialize)) {
            continue;
        }
        if (class_getInstanceMethod(targetMetaClass, selector)) {
            continue;
        }
        
        IMP imp = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);
        class_addMethod(targetMetaClass, selector, imp, types);
    }
}

// 构造函数，在 main 函数执行钱执行
__attribute__((constructor)) static void _pk_extension_inject_entry(void) {
    
    pthread_mutex_lock(&protocolsLoadingLock);

    unsigned classCount = 0;
//    获取类列表
    Class *allClasses = objc_copyClassList(&classCount);
    
    @autoreleasepool {
//      遍历所有类，如果该类实现了相应的协议，就把这个协议定义的方法加入到这个类的方法列表里面去
        for (unsigned protocolIndex = 0; protocolIndex < extendedProtcolCount; ++protocolIndex) {
            PKExtendedProtocol extendedProtcol = allExtendedProtocols[protocolIndex];
            for (unsigned classIndex = 0; classIndex < classCount; ++classIndex) {
                Class class = allClasses[classIndex];
                if (!class_conformsToProtocol(class, extendedProtcol.protocol)) {
                    continue;
                }
                _pk_extension_inject_class(class, extendedProtcol);
            }
        }
    }
    pthread_mutex_unlock(&protocolsLoadingLock);
    
    free(allClasses);
    free(allExtendedProtocols);
    extendedProtcolCount = 0, extendedProtcolCapacity = 0;
}
