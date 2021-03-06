/*
	Copyright (C) 2011 Quentin Mathe

	Author:  Quentin Mathe <quentin.mathe@gmail.com>
	Date:  November 2011
	License:  Modified BSD  (see COPYING)
 */

#import "OMBrowserController.h"
#import "OMAppController.h"
#import "OMBrowserContentController.h"
#import "OMCollectionAdditions.h"
#import "OMConstants.h"
#import "OMLayoutItemFactory.h"
#include <objc/runtime.h>

@implementation OMBrowserController

@synthesize contentViewItem, sourceListItem, viewPopUpItem, browsedGroup;

- (id) init
{
	SUPERINIT;
	[self setCurrentObjectType: nil];
	return self;
}

- (void) dealloc
{
	DESTROY(contentViewItem);
	DESTROY(sourceListItem);
	DESTROY(viewPopUpItem);
	DESTROY(statusLabelItem);
	DESTROY(browsedGroup);
	[super dealloc];
}

#pragma mark - 
#pragma mark Accessing UI Objects

- (void) setContentViewItem: (ETLayoutItemGroup *)anItem
{
	[self stopObserveObject: anItem forNotificationName: ETItemGroupSelectionDidChangeNotification];
	ASSIGN(contentViewItem, anItem);
	[self setInitialFocusedItem: anItem];
	[self startObserveObject: anItem
	     forNotificationName: ETItemGroupSelectionDidChangeNotification
	                selector: @selector(contentViewSelectionDidChange:)];
}

- (void) setSourceListItem: (ETLayoutItemGroup *)anItem
{
	[self stopObserveObject: anItem forNotificationName: ETItemGroupSelectionDidChangeNotification];
	ASSIGN(sourceListItem, anItem);
	[self startObserveObject: anItem
	     forNotificationName: ETItemGroupSelectionDidChangeNotification
	                selector: @selector(sourceListSelectionDidChange:)];
}

- (ETLayoutItemGroup *) topBarItem
{
	return (id)[[self content] itemForIdentifier: @"browserTopBar"];
}

- (ETLayoutItemGroup *) bodyItem
{
	return [[self sourceListItem] parentItem];
}

- (ETLayoutItemGroup *) contentViewWrapperItem
{
	return [[self contentViewItem] parentItem];
}

- (ETLayoutItemGroup *) tagFilterFieldItem
{
	return (id)[[self topBarItem] itemForIdentifier: @"tagFilterField"];
}

- (ETLayoutItemGroup *) tagFilterEditorItem
{
	return (id)[[self contentViewWrapperItem] itemForIdentifier: @"tagFilterEditor"];
}

- (ETLayoutItemGroup *) inspectorItem
{
	return (id)[[self bodyItem] itemForIdentifier: @"inspector"];
}

- (ETLayoutItemGroup *) whatGroupItem
{
	return (id)[sourceListItem itemAtIndex: 1];
}

#pragma mark -
#pragma mark Accessing Model Objects

- (void) setBrowsedGroup: (id <ETCollection>)aGroup
{
	ETAssert(aGroup != nil);

	id oldRepresentedObject = AUTORELEASE(RETAIN([sourceListItem representedObject]));

	// NOTE: We don't use -isEqual: to handle nil cases transparently
	if ([contentViewItem representedObject] == oldRepresentedObject) 
		return;

	ETLog(@"Browse group %@", aGroup);

	ASSIGN(browsedGroup, aGroup);
	[(id)[contentViewItem controller] prepareForNewRepresentedObject: aGroup];
	[[statusLabelItem view] setObjectValue: aGroup];

	[[self history] addObject: aGroup];
}

- (COSmartGroup *) allObjectGroup
{
	// TODO: Fragile way to access All Objects
	return [[[self whereGroup] contentArray] firstObject];
}

- (ETHistory *)history
{
	// TODO: Return 'Recently Visted' from WHEN group
	return nil;
}

- (COGroup *) whereGroup
{
	return [[sourceListItem firstItem] representedObject];
}

- (COGroup *) whenGroup
{
	return [[sourceListItem lastItem] representedObject];
}

#pragma mark -
#pragma mark Selection

- (id) allSelectedObjectsInContentView
{
	NSArray *selectedObjects =
		[[[[self contentViewItem] selectedItemsInLayout] mappedCollection] representedObject];
	
	if ([selectedObjects isEmpty])
	{
		selectedObjects = A([self browsedGroup]);
	}
	return selectedObjects;
}

- (id) selectedObjectInContentView
{
	id selectedObject = [[[[self contentViewItem] selectedItemsInLayout] firstObject] representedObject];

	if (selectedObject == nil)
	{
		selectedObject = [self browsedGroup];
	}
	return selectedObject;
}

- (NSArray *) selectedObjectsInSourceList
{
	return [[[[self sourceListItem] selectedItemsInLayout] mappedCollection] representedObject];
}

- (NSSet *) selectedTags
{
	NSMutableSet *tags = [NSMutableSet set];
	ETLayoutItemGroup *whatGroupItem = [self whatGroupItem];

	for (NSIndexPath *indexPath in [whatGroupItem selectionIndexPaths])
	{
		COObject *selectedObject = [[whatGroupItem itemAtIndexPath: indexPath] representedObject];
	
		if ([selectedObject isTag])
		{
			[tags addObject: selectedObject];
		}
		else
		{
			ETAssert([selectedObject isKindOfClass: [COTagGroup class]]);
			[tags addObjectsFromArray: [(COTagGroup *)selectedObject contentArray]];
		}
	}
	return tags;
}

- (COSmartGroup *) unionGroupWithTags: (id <ETCollection>)tags
{
	// TODO: Finish filtering on whenPredicate & whatPredicate & searchPredicate
	NSPredicate *predicate =
		[NSPredicate predicateWithFormat: @"ALL %@ IN tags", [self selectedTags]];
	COSmartGroup *tagFilteredGroup = AUTORELEASE([[COSmartGroup alloc]
		initWithObjectGraphContext: [COObjectGraphContext objectGraphContext]]);

	[tagFilteredGroup setTargetCollection:
		[COSmartGroup unionGroupWithCollections: [self whereGroup]]];
	[tagFilteredGroup setQuery: [COQuery queryWithPredicate: predicate]];

	return tagFilteredGroup;
}

#pragma mark -
#pragma mark Notifications

- (void) sourceListSelectionDidChange: (NSNotification *)aNotif
{
	ETLog(@"Did change selection in %@", [aNotif object]);
	NSArray *selectedObjects = [self selectedObjectsInSourceList];
	BOOL isSingleSelection = ([selectedObjects count] == 1);
	BOOL isMultipleSelectionInSingleCategory = ([selectedObjects count] > 1 
		&& [selectedObjects isSameKindAmongObjects]);

	if (isSingleSelection)
	{
		[self setBrowsedGroup: [selectedObjects firstObject]];
	}
	else if (isMultipleSelectionInSingleCategory)
	{
		/* Selected objects are collections (either libraries, tags, tag groups etc.) */
		[self setBrowsedGroup: [COSmartGroup unionGroupWithCollections: selectedObjects]];
	}
	else
	{
		[self setBrowsedGroup: [self unionGroupWithTags: [self selectedTags]]];
	}

	NSString *browserTitle = [[selectedObjects firstObject] name];
	BOOL isMultipleSelection = (isSingleSelection == NO);

	if (isMultipleSelection)
	{
		browserTitle = [browserTitle stringByAppendingString: _(@" and more")];
	}

	[[self content] setName: browserTitle];
}

- (void) contentViewSelectionDidChange: (NSNotification *)aNotif
{
	ETLog(@"Did change selection in %@", [aNotif object]);
	[self updateInspector];
}

#pragma mark -
#pragma mark Edition Coordinator

- (NSArray *) selectedFilterEditorTags
{
	return [[[[self tagFilterEditorItem] selectedItems] mappedCollection] representedObject];
}

- (void) syncTagFilterFieldFromEditor
{
	NSArray *filterTags = [self selectedFilterEditorTags];
	NSString *filterString = [(id)[[filterTags mappedCollection] name] componentsJoinedByString: @", "];
	
	[[self tagFilterFieldItem] setValue: filterString];
}

- (void) tagFilterEditorSelectionDidChange: (NSNotification *)aNotif
{
	[self syncTagFilterFieldFromEditor];
}

- (BOOL) isTagFilterItem: (ETLayoutItem *)anItem
{
	return [[anItem name] isEqual: _(@"Tag Filter")];
}

- (void) didBecomeFocusedItem: (ETLayoutItem *)anItem
{
	NSLog(@"Did become focused item %@", [anItem primitiveDescription]);

	BOOL isTagFilterEditorVisible = ([self tagFilterEditorItem] != nil);

	if ([self isTagFilterItem: anItem] == NO || isTagFilterEditorVisible)
		return;

	[self showTagFilterEditor];
}

- (void) didResignFocusedItem: (ETLayoutItem *)anItem
{
	NSLog(@"Did resign focused item %@", [anItem primitiveDescription]);

	/* For a tag just renamed in the tag filter editor */
	if ([[anItem parentItem] isEqual: [self tagFilterEditorItem]])
	{
		[self syncTagFilterFieldFromEditor];
	}
}

#pragma mark -
#pragma mark User Interface Item Validation

- (BOOL) isSingleSelectionInSourceList
{
	return ([[self selectedObjectsInSourceList] count] == 1);
}

- (BOOL) hasSelectionInContentView
{
	NSArray *selectedObjects = [self allSelectedObjectsInContentView];
	return ([selectedObjects count] > 0 && [selectedObjects isEqual: A([self browsedGroup])] == NO);
}

- (NSSet *) validatableItems
{
	return [NSSet setWithArray: [[self topBarItem] items]];
}

- (BOOL) validateItem: (ETLayoutItem *)anItem
{
	return [self validateUserInterfaceItem: (id)anItem];
}

- (BOOL) validateUserInterfaceItem: (id <NSValidatedUserInterfaceItem>)anItem
{
	if (sel_isEqual([anItem action], @selector(addNewObject:)))
	{
		if ([self isSingleSelectionInSourceList])
		{
			return ([self currentObjectType] != nil);
		}
		return NO;
	}
	else if (sel_isEqual([anItem action], @selector(delete:))
	      || sel_isEqual([anItem action], @selector(duplicate:)))
	{
		return ([self isSingleSelectionInSourceList] && [self hasSelectionInContentView]);
	}
	else if (sel_isEqual([anItem action], @selector(open:))
	      || sel_isEqual([anItem action], @selector(markVersion:))
	      || sel_isEqual([anItem action], @selector(revertTo:))
	      || sel_isEqual([anItem action], @selector(browseHistory:))
	      || sel_isEqual([anItem action], @selector(import:))
	      || sel_isEqual([anItem action], @selector(export:)))
	{
		return [self hasSelectionInContentView];
	}
	return YES;
}

#pragma mark -
#pragma mark Presentation

- (void) showTagFilterEditor
{
	COTagLibrary *tagLibrary = [[self editingContext] tagLibrary];
	NSSize editorSize = NSMakeSize([[self contentViewWrapperItem] width], [[OMLayoutItemFactory factory] defaultTagFilterEditorHeight]);
	ETLayoutItemGroup *editorItem =
		[[OMLayoutItemFactory factory] tagFilterEditorWithTagLibrary: tagLibrary
	                                                            size: editorSize
	                                                      controller: self];

	[self startObserveObject: editorItem forNotificationName: ETItemGroupSelectionDidChangeNotification selector: @selector(tagFilterEditorSelectionDidChange:)];
	
	[[self contentViewItem] setHeight: [[self contentViewItem] height] - [editorItem height]];
	[[self contentViewWrapperItem] insertItem: editorItem atIndex: 0];
}

- (void) hideTagFilterEditor
{
	ETLayoutItem *editorItem = [self tagFilterEditorItem];
	ETAssert([[self contentViewWrapperItem] containsItem: editorItem]);

	[self stopObserveObject: editorItem forNotificationName: ETItemGroupSelectionDidChangeNotification];

	[[self contentViewItem] setHeight: [[self contentViewItem] height] + [editorItem height]];
	[[self contentViewWrapperItem] removeItem: editorItem];
}

- (BOOL) isInspectorHidden
{
	return ([self inspectorItem] == nil);
}

- (void) showInspector
{
	NSSize size = NSMakeSize([[OMLayoutItemFactory factory] defaultInspectorWidth], [[self bodyItem] height]);
	ETLayoutItemGroup *inspectorItem =
		[[OMLayoutItemFactory factory] inspectorWithObject: [self selectedObjectInContentView]
	                                                  size: size
	                                            controller: self];
	[[self contentViewWrapperItem] setWidth: [[self contentViewWrapperItem] width] - [inspectorItem width]];
	[[self bodyItem] addItem: inspectorItem];
}

- (void) hideInspector
{
	ETAssert([[self bodyItem] containsItem: [self inspectorItem]]);
	[[self bodyItem] removeItem: [self inspectorItem]];
}

- (void) updateInspector
{
	if ([self isInspectorHidden])
		return;

	CGFloat oldInspectorWidth = [[self inspectorItem] width];

	[self hideInspector];
	/* Just resize the content view wrapper to match -showInspector expectations (we could simply 
	   do [contentViewWrapperItem updateLayoutRecursively: NO] too) */
	[[self contentViewWrapperItem] setWidth: [[self contentViewWrapperItem] width] + oldInspectorWidth];
	[self showInspector];
}

- (ETLayoutItem *) tagLibraryItem
{
	COLibrary *tagLibrary = [[self editingContext] tagLibrary];
	return [[[sourceListItem items] filteredArrayUsingPredicate: 
		[NSPredicate predicateWithFormat: @"representedObject == %@", tagLibrary]] firstObject];
}

#pragma mark -
#pragma mark Object Insertion and Deletion Actions

- (COCollection *) insertionCollectionForNewObject
{
	if ([self isSingleSelectionInSourceList] == NO)
		return nil;

	id selectedObject = [[self selectedObjectsInSourceList] firstObject];
	BOOL canInsertInto = ([selectedObject isKindOfClass: [COLibrary class]]);

	return (canInsertInto ? selectedObject : nil);
}

- (ETUTI *) currentObjectType
{
	return [[self insertionCollectionForNewObject] objectType];
}

- (IBAction) add: (id)sender
{
	[[contentViewItem controller] add: sender];
}

- (IBAction) addNewObject: (id)sender
{
	[self add: sender];
}

- (IBAction) addNewObjectFromTemplate: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

- (void) expandItem: (ETLayoutItem *)anItem
{
	[(NSOutlineView *)[[[self sourceListItem] layout] tableView]
		expandItem: anItem expandChildren: NO];
}

- (void) deselectAllInSourceList
{
	[[self sourceListItem] setSelectionIndexPaths: [NSArray array]];
}

- (void) selectTagGroupForInsertingTagInSourceList
{
	[self deselectAllInSourceList];

	NSArray *selectedTagGroupItems = [[self whatGroupItem] selectedItems];

	if ([selectedTagGroupItems isEmpty])
	{
		ETLayoutItem *unclassifiedTagGroupItem = [[self whatGroupItem] lastItem];
		[[self whatGroupItem] setSelectedItems: A(unclassifiedTagGroupItem)];
	}
	else
	{
		[[self whatGroupItem] setSelectedItems: A([selectedTagGroupItems firstObject])];
	}
}

- (void) insertNewTagInSelectedTagGroup
{
	COEditingContext *ctxt = [self editingContext];
	COGroup *tag = [[ctxt insertNewPersistentRootWithEntityName: @"Anonymous.COTag"] rootObject];

	[tag setName: _(@"Untitled")];

	/* Will invoke -addObject: on the Tag group */
	[(OMBrowserContentController *)[contentViewItem controller] addTag: tag];

	// FIXME: Look up the object type correctly and localize
	NSString *objType = @"Tag";
	NSDictionary *metadata = D(A(objType), kCOCommitMetadataShortDescriptionArguments);
	NSError *error = nil;

	[[self editingContext] commitWithIdentifier: kOMCommitCreate
	                                   metadata: metadata
	                                  undoTrack: [self undoTrack]
	                                      error: &error];
	[self handleCommitError: error];
}

- (IBAction) addNewTag: (id)sender
{
	[self expandItem: [self whatGroupItem]];
	[self selectTagGroupForInsertingTagInSourceList];
	[self insertNewTagInSelectedTagGroup];

	// TODO: [[contentViewItem lastItem] beginEditingForProperty: @"name"];
}

- (IBAction) addNewGroup: (id)sender
{
	// TODO: Implement New Smart Group...
}

- (IBAction) duplicate: (id)sender
{
	[(OMBrowserContentController *)[contentViewItem controller] duplicate];
	[[self allObjectGroup] refresh];
}

- (IBAction) remove: (id)sender
{
	[[contentViewItem controller] remove: sender];
	[[self allObjectGroup] refresh];
}

- (IBAction) delete: (id)sender
{
	[self remove: sender];
}

#pragma mark -
#pragma mark Presentation Actions

- (void) changePresentationViewToMenuItem: (NSMenuItem *)aMenuItem
{
	ETLayout *templateLayout = [aMenuItem representedObject];
	[contentViewItem setLayout: AUTORELEASE([templateLayout copy])];
}

- (NSString *) currentPresentationTitle
{
	return [[[[ETApp layoutItem] controller] ifResponds] currentPresentationTitle];
}

- (void) setCurrentPresentationTitle: (NSString *)aTitle
{
	[[[[ETApp layoutItem] controller] ifResponds] setCurrentPresentationTitle: aTitle];
}

- (void) updateForNewSelectedItemTitle: (NSString *)newTitle
                              oldTitle: (NSString *)oldTitle
                                inMenu: (NSMenu *)aMenu
{
	BOOL hasExpectedAppController = ([self currentPresentationTitle] != nil);

	if (hasExpectedAppController == NO)
		return;

	[[aMenu itemWithTitle: oldTitle] setState: NSOffState];
	[[aMenu itemWithTitle: newTitle] setState: NSOnState];
}

- (IBAction) changePresentationViewFromPopUp: (id)sender
{
	ETAssert(viewPopUpItem != nil);

	[self changePresentationViewToMenuItem: [[viewPopUpItem view] selectedItem]];

	NSString *newSelectedTitle = [[[viewPopUpItem view] selectedItem] title];
	
	[self updateForNewSelectedItemTitle: newSelectedTitle
	                           oldTitle: [self currentPresentationTitle]
	                             inMenu: [[ETApp viewMenuItem] submenu]];
	[self setCurrentPresentationTitle: newSelectedTitle];
}

- (IBAction) changePresentationViewFromMenuItem: (id)sender
{
	[self updateForNewSelectedItemTitle: [sender title]
	                           oldTitle: [self currentPresentationTitle]
	                             inMenu: [sender menu]];
	[self changePresentationViewToMenuItem: sender];

	[self setCurrentPresentationTitle: [sender title]];
	[(NSPopUpButton *)[viewPopUpItem view] selectItemWithTitle: [self currentPresentationTitle]];
}

- (IBAction) changeInspectorViewFromMenuItem: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

- (IBAction) toggleInspector: (id)sender
{
	if ([self isInspectorHidden])
	{
		[self showInspector];
	}
	else
	{
		[self hideInspector];
	}
}

- (IBAction) showInspectorInStandaloneWindow: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

#pragma mark -
#pragma mark Other Object Actions

- (IBAction) search: (id)sender
{
	NSString *searchString = [sender stringValue];
	
	ETLog(@"Search %@ with %@", [searchString description], [[contentViewItem controller] description]);
	
	if ([searchString isEqual: @""])
	{
		[[contentViewItem controller] setFilterPredicate: nil];
	}
	else
	{
		// TODO: Improve (Full-text, SQL, more properties, Object Matching integration)
		NSString *queryString =
		@"(name CONTAINS %@) OR (typeDescription CONTAINS %@) OR (tagDescription CONTAINS %@)";
		NSPredicate *predicate = [NSPredicate predicateWithFormat: queryString
			                                        argumentArray: A(searchString, searchString, searchString)];
		
		[[contentViewItem controller] setFilterPredicate: predicate];
	}
}

- (IBAction) filter: (id)sender
{
	
}

- (IBAction) resetTagFiltering: (id)sender
{
	id <ETFirstResponderSharingArea> responderArea =
		[[self tagFilterFieldItem] firstResponderSharingArea];
	BOOL isEditing = [[responderArea focusedItem] isEqual: [self tagFilterFieldItem]];

	if (isEditing)
	{
		[[ETTool activeTool] makeFirstResponder: nil];
	}
	/* Setting a nil value is not supported, -[ETLayoutItem syncView:withValue:] 
	   ignores such a change for a represented object (we might want not to 
	   ignore if both represented object value are nil, or convert nil to an 
	   empty string using the cell). */
	[[self tagFilterFieldItem] setValue: @""];

	[self hideTagFilterEditor];
}

- (IBAction) doubleClick: (id)sender
{
	id clickedObject = [[sender doubleClickedItem] representedObject];
	
	ETLog(@"Double click %@", [clickedObject description]);
	
	if ([clickedObject isGroup])
	{
		// TODO: Should use -openDocument: on OMAppController
		OMLayoutItemFactory *itemFactory = [OMLayoutItemFactory factory];
		ETLayoutItemGroup *browser =
			[itemFactory browserWithGroup: [[self sourceListItem] representedObject]
			               editingContext: [self editingContext]];
		
		[(OMBrowserController *)[browser controller] setBrowsedGroup: clickedObject];
		[[itemFactory windowGroup] addObject: browser];
	}
	else
	{
		ETLog(@"Open is not yet implemented!");
	}
}

- (IBAction) open: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

- (IBAction) markVersion: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

- (IBAction) revertTo: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

- (IBAction) browseHistory: (id)sender
{
	if ([[self selectedObjectInContentView] isPersistent] == NO)
		return;

	id <COTrack> track = [[[self selectedObjectInContentView] objectGraphContext] branch];
	ETLayoutItemGroup *browser =
		[[ETLayoutItemFactory factory] historyBrowserWithRepresentedObject: track
		                                                             title: nil];

	[[[ETLayoutItemFactory factory] windowGroup] addItem: browser];
}

- (IBAction) import: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

- (IBAction) export: (id)sender
{
	// TODO: Implement
	[self doesNotRecognizeSelector: _cmd];
}

- (BOOL) isSourceListFocused
{
	ETLayoutItem *focusedItem = [[self firstResponderSharingArea] focusedItem];

	return ([focusedItem isEqual: [self sourceListItem]]
	     || [[[self sourceListItem] selectedItemsInLayout] containsObject: focusedItem]);
}

- (IBAction) selectAllExceptInSourceList: (id)sender
{
	id responder = nil;

	if ([self isSourceListFocused])
	{
		responder = [[self contentViewItem] controller];
	}
	[ETApp sendAction: @selector(selectAll:) to: responder from: sender];
}

- (IBAction)undoInSelection: (id)sender
{
	// TODO: Support multiple selected objects by looking for the last edited 
	// object among them.
	// TODO: If we want to prevent undoing changes not committed by the Object Manager...
	// Check wether the revision to be undone was written in the main custom 
	// undo track. When it is not the case, disable Undo in Selection or skip 
	// the checked object (then test the next selected object).
	[[[self selectedObjectInContentView] commitTrack] undo];
}

@end
