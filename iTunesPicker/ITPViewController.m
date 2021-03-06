//
//  ITPViewController.m
//  iTunesPicker
//
//  Created by Denis Berton on 17/02/14.
//  Copyright (c) 2014 appcorner.it. All rights reserved.
//

#import "ITPViewController.h"
#import "ITPPickerTableViewController.h"
#import "ITPCountryItemChartsViewController.h"
#import "ITPAppPickerDetailViewController.h"
#import "ITPSideRightMenuViewController.h"

#import "SVProgressHUD.h"

@interface ITPViewController () <SwipeViewDataSource, SwipeViewDelegate, ITPMenuTableViewDelegate, ADBannerViewDelegate>
{
    CGRect filterCloseFrame,filterOpenFrame;
    BOOL pickersLoading;
    BOOL firstLoad;
    NSUInteger maxRecordToLoadForCountry;
    
    NSArray *rankingItems;
    NSArray *genreItems;
    NSUInteger rankingSelectedIndex;
    NSUInteger genreSelectedIndex;

    BOOL bannerIsVisible;
    
    NSDate* startLoadingDate;
}

@end

@implementation ITPViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    if(!IAD_BANNER_ENABLE)
    {
        [self.bannerView removeFromSuperview];
    }
    
    maxRecordToLoadForCountry = kITunesMaxLimitLoadEntities; //max iTunes API records
    
    pickersLoading = NO;
    firstLoad = YES;
    _swipeView.pagingEnabled = YES;
    
    self.pickerViews = [[NSMutableArray alloc]init];

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"save_picker_state"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkACKTypes:) name:NOTIFICATION_CHECK_ACK_TYPES object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self checkFirstLoad];
}

- (void)dealloc
{
    _swipeView.delegate = nil;
    _swipeView.dataSource = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

//-(void)didReceiveMemoryWarning
//{
//    [super didReceiveMemoryWarning];
//    [ACKITunesQuery cleanCacheExceptTypes:@[@(self.entitiesDatasources.entityType)]];
//}

#pragma mark public

- (void)reloadWithEntityType:(tITunesEntityType)entityType withMediaType:(tITunesMediaEntityType)mediaEntityType
{
    if(self.entitiesDatasources.entityType != entityType || self.entitiesDatasources.mediaEntityType != mediaEntityType)
    {
        NSString* userCountry = [self.entitiesDatasources.userCountry copy];
        NSArray* allPickerCountries = [[self.entitiesDatasources getAllCountries] copy];
        for (NSString* countryPicker in allPickerCountries) {
            [self removePickerTableViewForCountry:countryPicker];
        }
        
        self.entitiesDatasources = [[ACKEntitiesContainer alloc]initWithUserCountry:userCountry entityType:entityType mediaEntityType:mediaEntityType limit:maxRecordToLoadForCountry];

        [self updateEntityMunuPanels];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
        
        if(allPickerCountries.count == 0)
        {
            allPickerCountries = @[userCountry];
        }
        for (NSString* country in allPickerCountries) {
            [self addPickerTableViewForCountry:country];
        }
        [self saveStatePickerApps];
        [_swipeView reloadData];
    }
}

#pragma mark public filter

- (void)toggleMenuPanel:(tITPMenuFilterPanel)menuFilterPanel
{
    switch (menuFilterPanel) {
        case kITPMenuFilterPanelNone:
            [self closeAllPanelsExcept:nil];
            break;
        case kITPMenuFilterPanelRanking:
            [self closeAllPanelsExcept:self.leftPanel];
            [self.leftPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
            }];
            break;
        case kITPMenuFilterPanelGenre:
            [self closeAllPanelsExcept:self.rightPanel];
            [self.rightPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
            }];
            break;
        default:
            break;
    }
}

-(NSString*)getSelectedFilterLabel:(tITPMenuFilterPanel)menuFilterPanel
{
    if(menuFilterPanel == kITPMenuFilterPanelRanking)
    {
        return NSLocalizedString(rankingItems[rankingSelectedIndex],@"");
    }
    return NSLocalizedString(genreItems[genreSelectedIndex],@"");
}

-(NSInteger)getFilterCountLabels:(tITPMenuFilterPanel)menuFilterPanel
{
    if(menuFilterPanel == kITPMenuFilterPanelRanking)
    {
        return rankingItems.count;
    }
    return genreItems.count;
}

- (void)openCountriesPicker {
    [self closeAllPanelsExcept:nil];
    ITPCountryItemChartsViewController *vc = [[ITPCountryItemChartsViewController alloc] initWithStyle:UITableViewStylePlain
                                                                                          allCountries:[ACKITunesQuery getITunesStoreCountries]
                                                                                     selectedCountries:[[NSSet alloc]initWithArray:[self.entitiesDatasources getAllCountries]]
                                                                                           userCountry:self.entitiesDatasources.userCountry
                                                                                           multiSelect:YES
                                                                                               isModal:NO];
    vc.countriesSelectionLimit = MAX_OPENED_PICKERS;
    vc.completionBlock = ^(NSArray *countries){
        NSArray* allPickerCountries = [[self.entitiesDatasources getAllCountries] copy];
        for (NSString* countryPicker in allPickerCountries) {
            if(![countries containsObject:countryPicker])
            {
                [self removePickerTableViewForCountry:countryPicker];
            }
        }
        for (NSString* country in countries) {
            if(![allPickerCountries containsObject:country])
            {
                [self addPickerTableViewForCountry:country];
            }
        }
        [self saveStatePickerApps];
        [_swipeView reloadData];
    };
    
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openDiscoverView
{
    [self closeAllPanelsExcept:nil];
    ITPPickerTableViewController* pickerTableView = [[ITPPickerTableViewController alloc]initWithNibName:nil bundle:nil];
    pickerTableView.delegate = self;
    NSArray* data = [self.entitiesDatasources mergeEntitiesInCountriesExcludeDuplicate:YES
                                                                  excludeNotInITunesUserCountry:YES
                                                                           excludeInUserCountry:YES];
    [pickerTableView showEntities:data keepEntitiesNotInCountry:NO highlightCells:NO completionBlock:nil];
    [self.navigationController pushViewController:pickerTableView animated:YES];
}

- (void)openGlobalRankingView
{
    [self closeAllPanelsExcept:nil];
    ITPPickerTableViewController* pickerTableView = [[ITPPickerTableViewController alloc]initWithNibName:nil bundle:nil];
    pickerTableView.delegate = self;
    NSArray* data = [self.entitiesDatasources mergeEntitiesInCountriesExcludeDuplicate:YES
                                                         excludeNotInITunesUserCountry:NO
                                                                  excludeInUserCountry:NO];
    data = [self.entitiesDatasources orderByCalculatedGlobalRanking:data];
    [pickerTableView showEntities:data keepEntitiesNotInCountry:YES highlightCells:YES completionBlock:nil];
    [self.navigationController pushViewController:pickerTableView animated:YES];
}


- (void)openUserCountryPicker {
    ITPCountryItemChartsViewController *vc = [[ITPCountryItemChartsViewController alloc] initWithStyle:UITableViewStylePlain
                                                                                          allCountries:[ACKITunesQuery getITunesStoreCountries]
                                                                                     selectedCountries:nil
                                                                                           userCountry:[NSLocale preferredLanguages][0]
                                                                                           multiSelect:NO
                                                                                              isModal:!firstLoad];
    
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:vc];
    vc.navigationItem.title=NSLocalizedString(@"countries.picker.title",nil);
    vc.completionBlock = ^(NSArray *countries){
        [navigation dismissViewControllerAnimated:YES completion:NO];
        if(self.entitiesDatasources)
        {
            NSArray* allPickerCountries = [[self.entitiesDatasources getAllCountries] copy];
            for (NSString* countryPicker in allPickerCountries) {
                [self removePickerTableViewForCountry:countryPicker];
            }
        }
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray *types = [defaults arrayForKey:DEFAULT_ACK_TYPES_KEY];
        
        tITunesEntityType entityType = self.entitiesDatasources?self.entitiesDatasources.entityType:[types[0] intValue];
        tITunesMediaEntityType mediaType = self.entitiesDatasources?self.entitiesDatasources.mediaEntityType:kITunesMediaEntityTypeDefaultForEntity;
        self.entitiesDatasources = [[ACKEntitiesContainer alloc]initWithUserCountry:countries[0] entityType:entityType mediaEntityType:mediaType limit:maxRecordToLoadForCountry];
        [self setupMenuPanels];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
        
        [self addPickerTableViewForCountry:countries[0]];
        if(firstLoad)
        {
            for (NSString* firstLoadCountry in DEFAULT_COUNTRIES) {
                if(![firstLoadCountry isEqualToString:countries[0]] && [[ACKITunesQuery getITunesStoreCountries] containsObject:firstLoadCountry])
                {
                    [self addPickerTableViewForCountry:firstLoadCountry];
                }
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_CHECK_ACK_TYPES_UPDATED object:self userInfo:@{NOTIFICATION_PARAM_ENTITY_TYPE:[NSNumber numberWithInt:entityType],NOTIFICATION_PARAM_ENTITY_MEDIA_TYPE:[NSNumber numberWithInt:mediaType]}];
        [self saveStatePickerApps];
        [_swipeView reloadData];
        if(firstLoad)
        {
            firstLoad = NO;
        }
    };
    
    [self presentViewController:navigation animated:YES completion:nil];
}

#pragma mark ITPViewControllerDelegate

-(void)showPickerAtIndex:(NSInteger)index
{
    [_swipeView scrollToItemAtIndex:index duration:0.5];
}

-(void)selectEntity:(ACKITunesEntity*)entity
{
    NSArray* indexCharts = [self.entitiesDatasources getIndexesFromEntity:entity];
    
    BOOL indexFound = NO;
    for (NSNumber* index in indexCharts) {
        NSInteger position = [index integerValue];
        if(position != NSNotFound)
        {
            indexFound = YES;
            break;
        }
    }
    
    if(!indexFound)
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"App not in rankings",nil) message:NSLocalizedString(@"The selected App is not present in the rankings of countries loaded.",nil) delegate:self cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Cancel",nil), nil];
        [alert show];
        return;
    }
    
    ITPCountryItemChartsViewController *vc = [[ITPCountryItemChartsViewController alloc] initWithStyle:UITableViewStylePlain
                                                                                          allCountries:[self.entitiesDatasources getAllCountries]
                                                                                           indexCharts:indexCharts
                                                                                           userCountry:self.entitiesDatasources.userCountry
                                                                                                  item:entity];
    vc.completionBlock = ^(NSArray *countries){};
    
    [self.navigationController pushViewController:vc animated:YES];
}

-(void)openITunesEntityDetail:(ACKITunesEntity*)entity
{
    if([entity isKindOfClass:[ACKApp class]]){
        ITPAppPickerDetailViewController* detailController = [[ITPAppPickerDetailViewController alloc]initWithNibName:nil bundle:nil];
        detailController.appObject = (ACKApp*)entity;
        ITPPickerTableViewController* picker = entity.userData;
        detailController.pickerCountry = picker.country?picker.country:entity.country;
        detailController.allowsSelection = picker.loadState != kITPLoadStateArtist;
        entity.userData = nil;
        detailController.delegate = self;
        [self.navigationController pushViewController:detailController animated:YES];
    }
}

-(tITunesMediaEntityType)getSearchITunesMediaEntityType
{
  if(self.entitiesDatasources.entityType == kITunesEntityTypeSoftware)
  {
      return self.entitiesDatasources.mediaEntityType;
  }
  else if(self.entitiesDatasources.entityType == kITunesEntityTypeMusic)
  {
      switch (rankingSelectedIndex) {
          case kITunesMusicChartTypeTopAlbums:
              return kITunesMediaEntityTypeMusicAlbum;
              break;
              
          case kITunesMusicChartTypeTopSongs:
              return kITunesMediaEntityTypeMusicSong;
              break;
      }
  }
  else if(self.entitiesDatasources.entityType == kITunesEntityTypeMovie)
  {
      return kITunesMediaEntityTypeMovie;
  }
  else if(self.entitiesDatasources.entityType == kITunesEntityTypeEBook)
  {
      return kITunesMediaEntityTypeEBook;
  }
  else if(self.entitiesDatasources.entityType == kITunesEntityTypeMusicVideo)
  {
      return kITunesMediaEntityTypeMusicVideoMusic;
  }
  return kITunesMediaEntityTypeSoftware;  //default
}

#pragma mark SwipeViewDataSource

- (NSInteger)numberOfItemsInSwipeView:(SwipeView *)swipeView
{
    return  self.entitiesDatasources.datasourcesCount;
}

- (UIView *)swipeView:(SwipeView *)swipeView viewForItemAtIndex:(NSInteger)index reusingView:(UIView *)view
{
    ITPPickerTableViewController* picker = (ITPPickerTableViewController*)self.pickerViews[index];
    return picker.view;
}

#pragma mark SwipeViewDelegate

- (CGSize)swipeViewItemSize:(SwipeView *)swipeView
{
    return self.swipeView.bounds.size;
}

- (void)swipeView:(SwipeView *)swipeView didSelectItemAtIndex:(NSInteger)index
{
    ITPPickerTableViewController* picker = ((ITPPickerTableViewController*)self.pickerViews[index]);
    [picker.searchBar resignFirstResponder];
}

-(void)showLoadingHUD:(BOOL)loading sender:(id)sender
{
    if(pickersLoading == loading)
    {
        return;
    }
    
    if(sender && [self.pickerViews containsObject:sender])
    {
        BOOL tmpPickersLoading = NO;
        for (ITPPickerTableViewController* pickerTableView in self.pickerViews) {
            tmpPickersLoading = tmpPickersLoading || pickerTableView.loading;
        }
        
        if(tmpPickersLoading == pickersLoading)
        {
            return;
        }
        pickersLoading = tmpPickersLoading;
    }
    else
    {
        pickersLoading = loading;
    }
    
    if(pickersLoading)
    {
        startLoadingDate = [NSDate date];
        [SVProgressHUD showWithMaskType:SVProgressHUDMaskTypeGradient];
    }
    else
    {
#if DEBUG
        NSLog(@"Loading time %f",[[NSDate date] timeIntervalSinceDate:startLoadingDate]);
#endif
        [SVProgressHUD dismiss];
    }
}

#pragma mark private

-(ITPPickerTableViewController*) addPickerTableViewForCountry:(NSString*)country
{
    ITPPickerTableViewController* pickerTableView = [[ITPPickerTableViewController alloc]initWithNibName:nil bundle:nil];
    pickerTableView.delegate = self;
    [self.pickerViews addObject:pickerTableView];
    
    [pickerTableView loadChartInITunesStoreCountry:country withType:rankingSelectedIndex withGenre:genreSelectedIndex completionBlock:^(NSArray *array, NSError *err) {
        [_swipeView reloadData];
    }];
    
    return pickerTableView;
}

-(void) refreshAllPickers
{
    NSInteger i = 0;
    for (ITPPickerTableViewController* pickerTableView in self.pickerViews) {
        [pickerTableView loadChartInITunesStoreCountry:[self.entitiesDatasources getAllCountries][i] withType:rankingSelectedIndex withGenre:genreSelectedIndex completionBlock:^(NSArray *array, NSError *err) {
            [_swipeView reloadData];
        }];
        i++;
    }
}

-(void) removePickerTableViewForCountry:(NSString*)country
{
    NSInteger index = [[self.entitiesDatasources getAllCountries]indexOfObject:country];
    if(index ==  NSNotFound)
    {
        return;
    }
    [self.entitiesDatasources removeDatasourceAtIndex:index];
    [self.pickerViews removeObjectAtIndex:index];
    [_swipeView reloadData];
}

-(void) checkFirstLoad
{
    if(firstLoad)
    {
        [self loadPickerState];
        if(!self.entitiesDatasources)
        {
            [self openUserCountryPicker];
        }
        else
        {
            firstLoad = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_CHECK_ACK_TYPES_UPDATED object:self userInfo:@{NOTIFICATION_PARAM_ENTITY_TYPE:[NSNumber numberWithInt:self.entitiesDatasources.entityType],NOTIFICATION_PARAM_ENTITY_MEDIA_TYPE:[NSNumber numberWithInt:self.entitiesDatasources.mediaEntityType]}];            
        }
    }
    else
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_CHECK_ACK_TYPES_UPDATED object:self userInfo:@{NOTIFICATION_PARAM_ENTITY_TYPE:[NSNumber numberWithInt:self.entitiesDatasources.entityType],NOTIFICATION_PARAM_ENTITY_MEDIA_TYPE:[NSNumber numberWithInt:self.entitiesDatasources.mediaEntityType]}];
    }
}

#pragma mark - filters

-(void)setupMenuPanels
{
    if(!self.leftPanel){
        self.leftPanel = [[ITPMenuTableViewController alloc]initWithNibName:nil bundle:nil];
    }
    self.leftPanel.type = kPAPMenuPickerTypeRanking;
    self.leftPanel.openDirection = kPAPMenuOpenDirectionRight;
    self.leftPanel.delegate = self;
    
    if(!self.rightPanel){
        self.rightPanel = [[ITPMenuTableViewController alloc]initWithNibName:nil bundle:nil];
    }
    self.rightPanel.type = kPAPMenuPickerTypeGenre;
    self.rightPanel.openDirection = kPAPMenuOpenDirectionLeft;
    self.rightPanel.delegate = self;
    
    [self updateEntityMunuPanels];
    
    [self.view addSubview:self.leftPanel.view];
    self.leftPanel.openFrame = self.swipeView.frame;
    self.leftPanel.backgroundAreaDismissRect = self.swipeView.frame;
    
    [self.view addSubview:self.rightPanel.view];
    self.rightPanel.openFrame = self.swipeView.frame;
    self.rightPanel.backgroundAreaDismissRect = self.swipeView.frame;
    
}

-(void) updateEntityMunuPanels
{
    if(self.entitiesDatasources.entityType == kITunesEntityTypeSoftware)
    {
        switch (self.entitiesDatasources.mediaEntityType) {
            case kITunesMediaEntityTypeSoftwareiPad:
                rankingItems = [ACKITunesQuery getAppIPadChartType];
                genreItems = [ACKITunesQuery getAppGenreType];
                break;

            case kITunesMediaEntityTypeSoftwareMac:
                rankingItems = [ACKITunesQuery getAppMacChartType];
                genreItems = [ACKITunesQuery getAppMacGenreType];
                break;
                
            default:
                rankingItems = [ACKITunesQuery getAppChartType];
                genreItems = [ACKITunesQuery getAppGenreType];
                break;
        }
    }
    else if(self.entitiesDatasources.entityType == kITunesEntityTypeMusic)
    {
        rankingItems = [ACKITunesQuery getMusicChartType];
        genreItems = [ACKITunesQuery getMusicGenreType];
    }
    else if(self.entitiesDatasources.entityType == kITunesEntityTypeMovie)
    {
        rankingItems = [ACKITunesQuery getMovieChartType];
        genreItems = [ACKITunesQuery getMovieGenreType];
    }
    else if(self.entitiesDatasources.entityType == kITunesEntityTypeEBook)
    {
        rankingItems = [ACKITunesQuery getBookChartType];
        genreItems = [ACKITunesQuery getBookGenreType];
    }
    else if(self.entitiesDatasources.entityType == kITunesEntityTypeMusicVideo)
    {
        rankingItems = [ACKITunesQuery getMusicVideosChartType];
        genreItems = [ACKITunesQuery getMusicVideosGenreType];
    }
    else
    {
        rankingItems= [ACKITunesQuery getAppChartType];
        genreItems = [ACKITunesQuery getAppGenreType];
    }
    self.leftPanel.items = [rankingItems copy];
    self.rightPanel.items = [genreItems copy];
}

-(void)valueSelectedAtIndex:(NSInteger)index forType:(tPAPMenuPickerType)type refreshPickers:(BOOL)refresh
{
    switch (type) {
        case kPAPMenuPickerTypeRanking:
            rankingSelectedIndex = index;
            if(self.leftPanel.isOpen)
                [self toggleMenuPanel:kITPMenuFilterPanelRanking];
            [self.leftPanel.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
            break;
        case kPAPMenuPickerTypeGenre:
            genreSelectedIndex = index;
            if(self.rightPanel.isOpen)
                [self toggleMenuPanel:kITPMenuFilterPanelGenre];
            [self.rightPanel.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
            break;
    }
    if(refresh)
    {
        [self saveStatePickerApps];
        [self refreshAllPickers];
    }
}

-(void) closeAllPanelsExcept:(ITPMenuTableViewController*)panel
{
    if(panel != self.leftPanel && self.leftPanel.isOpen)
        [self.leftPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
        }];
    if(panel != self.rightPanel && self.rightPanel.isOpen)
        [self.rightPanel togglePanelWithCompletionBlock:^(BOOL isOpen) {
        }];
}

#pragma mark - load/save picker state

-(void)loadPickerState
{
    NSDictionary *defaultUserDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSNumber numberWithInteger:-1], @"saved_picker_ranking",
                                         [NSNumber numberWithInteger:-1], @"saved_picker_genre",
                                         [NSNumber numberWithInteger:10], DEFAULT_ACK_CHART_ITEMS_KEY,
                                         [[NSArray alloc]init], @"saved_picker_countries",
                                         @"", @"saved_picker_usercountry",
                                         nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultUserDefaults];
    NSArray *types = [[NSUserDefaults standardUserDefaults] arrayForKey:DEFAULT_ACK_TYPES_KEY];
    
    BOOL loadDefault = YES;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"save_picker_state"])
    {
        NSInteger ranking = [[NSUserDefaults standardUserDefaults] integerForKey:@"saved_picker_ranking"];
        NSInteger genre = [[NSUserDefaults standardUserDefaults] integerForKey:@"saved_picker_genre"];
        NSInteger entityType = [[NSUserDefaults standardUserDefaults] integerForKey:@"saved_picker_entitytype"];
        NSInteger mediaType = [[NSUserDefaults standardUserDefaults] integerForKey:@"saved_picker_mediaentitytype"];
        NSArray* countries = [[NSUserDefaults standardUserDefaults] arrayForKey:@"saved_picker_countries"];
        NSString* userCountry = [[NSUserDefaults standardUserDefaults] stringForKey:@"saved_picker_usercountry"];
        
        if(ranking != -1 && genre != -1 && countries.count > 0 && [types containsObject:@(entityType)])
        {
            self.entitiesDatasources = [[ACKEntitiesContainer alloc]initWithUserCountry:userCountry entityType:entityType mediaEntityType:mediaType limit:maxRecordToLoadForCountry];
            [self setupMenuPanels];
            [self valueSelectedAtIndex:ranking forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
            [self valueSelectedAtIndex:genre forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
            for (NSString* country in countries) {
                [self addPickerTableViewForCountry:country];
            }
            loadDefault = NO;
        }
    }
    if(loadDefault)
    {
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeRanking refreshPickers:NO];
        [self valueSelectedAtIndex:0 forType:kPAPMenuPickerTypeGenre refreshPickers:NO];
    }
    else
    {
        [_swipeView reloadData];
    }
}

-(void)saveStatePickerApps
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"save_picker_state"])
    {
        [[NSUserDefaults standardUserDefaults] setInteger:rankingSelectedIndex forKey:@"saved_picker_ranking"];
        [[NSUserDefaults standardUserDefaults] setInteger:genreSelectedIndex forKey:@"saved_picker_genre"];
        [[NSUserDefaults standardUserDefaults] setInteger:self.entitiesDatasources.entityType forKey:@"saved_picker_entitytype"];
        [[NSUserDefaults standardUserDefaults] setInteger:self.entitiesDatasources.mediaEntityType forKey:@"saved_picker_mediaentitytype"];
        [[NSUserDefaults standardUserDefaults] setValue:[self.entitiesDatasources getAllCountries] forKey:@"saved_picker_countries"];
        [[NSUserDefaults standardUserDefaults] setValue:self.entitiesDatasources.userCountry forKey:@"saved_picker_usercountry"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

#pragma mark - Notifications

-(void)checkACKTypes:(NSNotification*)notification
{
    if(self.entitiesDatasources)
    {
        NSArray *types = [[NSUserDefaults standardUserDefaults] arrayForKey:DEFAULT_ACK_TYPES_KEY];
        if(![types containsObject:@(self.entitiesDatasources.entityType)])
        {
            firstLoad = YES;
            self.entitiesDatasources = nil;
            [self checkFirstLoad];
        }
    }
}

#pragma mark - ADBannerViewDelegate

- (BOOL)bannerViewActionShouldBegin:(ADBannerView *)banner willLeaveApplication:(BOOL)willLeave
{
    return YES;
}

- (void)bannerViewDidLoadAd:(ADBannerView *)banner
{
    if (!bannerIsVisible)
    {
        [UIView animateWithDuration:0.2 animations:^{
            self.swipeViewVerticalSpaceLayoutConstraint.constant += self.bannerHeightLayoutConstraint.constant;
            [self.view setNeedsUpdateConstraints];
        } completion:^(BOOL finished) {
            [self setupMenuPanels];
        }];
        bannerIsVisible = YES;
    }
}

- (void)bannerView:(ADBannerView *)banner didFailToReceiveAdWithError:(NSError *)error
{
    if (bannerIsVisible)
    {
        [UIView animateWithDuration:0.2 animations:^{
            self.swipeViewVerticalSpaceLayoutConstraint.constant -= self.bannerHeightLayoutConstraint.constant;
            [self.view setNeedsUpdateConstraints];
        } completion:^(BOOL finished) {
            [self setupMenuPanels];
        }];
        bannerIsVisible = NO;
    }
}

@end
