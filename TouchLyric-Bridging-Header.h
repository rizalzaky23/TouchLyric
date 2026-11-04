#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

// Private DFRFoundation symbols – we will load them dynamically at runtime.
typedef void (*DFRElementSetControlStripPresenceForIdentifierFunc)(NSString *identifier, BOOL present);
typedef void (*NSTouchBarPresentSystemModalTouchBarFunc)(NSTouchBar *touchBar);
typedef void (*NSTouchBarDismissSystemModalTouchBarFunc)(NSTouchBar *touchBar);

// Helper to retrieve function pointers via dlsym.
static inline void *DFR_GetSymbol(const char *symbolName) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW);
    if (!handle) return NULL;
    return dlsym(handle, symbolName);
}
