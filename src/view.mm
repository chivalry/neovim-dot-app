#include <string>
#include "vim.h"

#import <Cocoa/Cocoa.h>
#import "view.h"

@implementation VimView

extern int x,y;

- (id)initWithFrame:(NSRect)frame vim:(Vim *)vim
{
    if (self = [super initWithFrame:frame]) {
        mVim = vim;
        mCanvas = [[NSImage alloc] initWithSize:CGSizeMake(1000, 1000)];
        mBackgroundColor = [[NSColor whiteColor] retain];
        mForegroundColor = [[NSColor blackColor] retain];
        mTextAttrs = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
            mForegroundColor, NSForegroundColorAttributeName,
            mBackgroundColor, NSBackgroundColorAttributeName,
            nil
        ] retain];
        mWaitAck = 0;

        mFont = [NSFont fontWithName:@"Menlo" size:11.0];
        [mFont retain];

        mCharSize.width = [mFont advancementForGlyph:' '].width;
        mCharSize.height = 17;
    }
    return self;
}

- (id)initWithCellSize:(CGSize)cellSize vim:(Vim *)vim
{
    NSRect frame = CGRectMake(0, 0, 100, 100);

    if (self = [self initWithFrame:frame vim:vim]) {
        frame.size = [self viewSizeFromCellSize:cellSize];
        [self setFrame:frame];
    }
    return self;
}

- (void)drawRect:(NSRect)rect
{
    [mBackgroundColor setFill];
    NSRectFill(rect);

    [mCanvas drawInRect:rect fromRect:rect operation:NSCompositeSourceOver fraction:1.0];
    [self drawCursor];
}

/* Draw a shitty cursor. TODO: Either:
    1) Figure out how to make Cocoa invert the display at the cursor pos
    2) Start keeping a screen character buffer */
- (void)drawCursor
{
    NSRect cellRect;

    if (mInsertMode)
        cellRect = CGRectMake(x, y, .2, 1);
    else
        cellRect = CGRectMake(x, y+1, 1, .3);

    NSRect viewRect = [self viewRectFromCellRect:cellRect];
    [mForegroundColor set];
    NSRectFill(viewRect);
}


/* -- Input -- */

/* When the user presses a key, put it in the keyqueue, and schedule 
   sendKeys */
- (void)keyDown:(NSEvent *)event
{
    [event retain];
    mKeyQueue.push_back(event);
    [self performSelector:@selector(sendKeys) withObject:nil afterDelay:0];
}

/* If the user hasn't hit any new keys, send all the keypresses in the keyqueue
   to Vim */
- (void)sendKeys
{
    if (mWaitAck)
        return;

    if (mKeyQueue.empty())
        return;

    NSMutableArray *array = [[NSMutableArray alloc] init];

    std::string raw;
    for (NSEvent *event: mKeyQueue) {
        int flags = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;

        if ([[event characters] isEqualToString:@"<"]) {
            raw += "<Char-0x3c>";
        }
        else if ([self shouldPassThrough:event]) {
            raw += [[event characters] UTF8String];
        }
        else {
            [array addObject:event];
        }
        [event release];
    }

    [self interpretKeyEvents:array];
    [array release];

    if (raw.size())
        [self vimInput:raw];

    mKeyQueue.clear();
}

/* Send an input string to Vim. */
- (void)vimInput:(const std::string &)input
{
    mWaitAck += 1;
    mVim->vim_input(input).then([self]() {
        mWaitAck -= 1;
        if (mWaitAck == 0)
            [self sendKeys];
    });
}

/* true if the key event should go directly to Vim; false if it
   should go to OS X */
- (bool)shouldPassThrough:(NSEvent *)event
{
    int flags = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;

    if (flags == NSControlKeyMask)
        return true;

    if ([[event characters] isEqualToString:@"\x1b"])
        return true;

    return false;
}

- (void)insertText:(id)string
{
    std::string input = [(NSString *)string UTF8String];
    [self vimInput:input];
}

- (void)deleteBackward:(id)sender { [self vimInput:"\x08"]; }
- (void)deleteForward: (id)sender { [self vimInput:"<Del>"]; }
- (void)insertNewline: (id)sender { [self vimInput:"\x0d"]; }
- (void)insertTab:     (id)sender { [self vimInput:"\t"]; }
- (void)insertBacktab: (id)sender { [self vimInput:"\x15"]; }



/* -- Resizing -- */

- (void)viewDidEndLiveResize
{
    [self display];
}

- (void)requestResize:(CGSize)cellSize
{
    int xCells = (int)cellSize.width;
    int yCells = (int)cellSize.height;

    if (xCells == mXCells && yCells == mYCells)
        return;

    if (mVim)
        mVim->ui_try_resize((int)cellSize.width, (int)cellSize.height);
}


/* -- Coordinate conversions -- */

- (NSRect)viewRectFromCellRect:(NSRect)cellRect
{
    CGFloat sy1 = cellRect.origin.y + cellRect.size.height;

    NSRect viewRect;
    viewRect.origin.x = cellRect.origin.x * mCharSize.width;
    viewRect.origin.y = [self frame].size.height - sy1 * mCharSize.height;
    viewRect.size = [self viewSizeFromCellSize:cellRect.size];
    return viewRect;
}

- (CGSize)viewSizeFromCellSize:(CGSize)cellSize
{
    return CGSizeMake(
        cellSize.width * mCharSize.width,
        cellSize.height * mCharSize.height
    );
}

- (CGSize)cellSizeInsideViewSize:(CGSize)viewSize
{
    CGSize cellSize;
    cellSize.width = int(viewSize.width / mCharSize.width);
    cellSize.height = int(viewSize.height / mCharSize.height);
    return cellSize;
}

@end
