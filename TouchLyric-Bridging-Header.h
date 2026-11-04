#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

@interface NSTouchBarItem (DFRPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (DFRPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

static inline void DFR_SetControlStripPresence(NSString *identifier, BOOL present) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW);
    if (!handle) return;
    typedef void (*DFRElementSetControlStripPresenceForIdentifierFunc)(NSString *, BOOL);
    DFRElementSetControlStripPresenceForIdentifierFunc fn = (DFRElementSetControlStripPresenceForIdentifierFunc)dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier");
    if (fn) fn(identifier, present);
}

static inline void DFR_SetShowsCloseBox(BOOL showsCloseBox) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW);
    if (!handle) return;
    typedef void (*DFRSystemModalShowsCloseBoxWhenExpandedFunc)(BOOL);
    DFRSystemModalShowsCloseBoxWhenExpandedFunc fn = (DFRSystemModalShowsCloseBoxWhenExpandedFunc)dlsym(handle, "DFRSystemModalShowsCloseBoxWhenExpanded");
    if (fn) fn(showsCloseBox);
}
