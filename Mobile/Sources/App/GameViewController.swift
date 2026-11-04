import UIKit
import UniformTypeIdentifiers

final class GameViewController:UIViewController,UIDocumentPickerDelegate,UIScrollViewDelegate {
    let library=ROMLibrary(),session=EmulationSession()
    lazy var covers=CoverLoader(library:library)
    let machine=MachineCanvas()
    private let pickerScroll=UIScrollView(),pickerContent=UIView()
    private let showcaseLight=SpatialShowcaseLight()
    private let pages=UIPageControl()
    private var explicitCardPage:Int?
    private let homeBrand=UIStackView(),homeBrandLogo=UIImageView(),homeBrandName=UILabel()
    private let themeShelf=GameShelfScrollView(),themeCards=UIStackView(),themeHeading=UILabel()
    private var themeWidth:CGFloat=300,themeHeight:CGFloat=300,themeViewport:CGFloat=0
    private var themeSpacing:CGFloat{isPhone && (!selectingTheme || model == .gbc) ? -140:24}
    private var themeStride:CGFloat{themeWidth+themeSpacing}
    private var themeSizeConstraints:[NSLayoutConstraint]=[]
    private var shelfCenter:NSLayoutConstraint!,shelfHeight:NSLayoutConstraint!
    private let menuHandle=UIButton(type:.system),menuShade=UIControl(),menuPanel=UIView(),menuRows=UIStackView()
    private var menuOpen=false,menuPausedGame=false
    private let nav=UIStackView(),titleButton=UIButton(type:.system),actions=UIStackView(),home=UIStackView(),shelf=GameShelfScrollView(),cards=UIStackView(),emptyLabel=UILabel(),busy=UIActivityIndicatorView(style:.large)
    private var isPhone:Bool{UIDevice.current.userInterfaceIdiom == .phone}
    private var cardWidth:CGFloat{
        let size=isPhone && model == .gbc ? CGSize(width:min(view.bounds.width,view.bounds.height),height:max(view.bounds.width,view.bounds.height)):view.bounds.size
        let fit=MobileLayout(model:model,viewport:size,topInset:isPhone && model == .gbc ? 62:view.safeAreaInsets.top,bottomInset:isPhone && model == .gbc ? 34:view.safeAreaInsets.bottom,verticalPosition:0.5,nativePhone:isPhone,leftInset:isPhone && model != .gbc ? view.safeAreaInsets.left:0,rightInset:isPhone && model != .gbc ? view.safeAreaInsets.right:0)
        let ratio:CGFloat=model == .psp ? 1:CartridgeSlot.load(model)?.ratio ?? 1
        let nativeWidth:CGFloat=model == .psp ? 260*SpatialMachine.mediaScale("psp"):CartridgeSlot.load(model)?.cardWidth ?? 148
        let top:CGFloat=isPhone && model == .gbc ? 62:view.safeAreaInsets.top,bottom:CGFloat=isPhone && model == .gbc ? 34:view.safeAreaInsets.bottom
        let left:CGFloat=isPhone && model == .gbc ? 0:view.safeAreaInsets.left,right:CGFloat=isPhone && model == .gbc ? 0:view.safeAreaInsets.right
        let area=CGRect(x:left+12,y:top+(isPhone ? 8:72),width:max(1,size.width-left-right-24),height:max(1,size.height-top-bottom-(isPhone ? 16:88)))
        let staging=SpatialMachine.loadingFrame(model:model.rawValue,size:fit.geometry.size,available:area,maxScale:fit.scale,mediaHeight:nativeWidth*ratio)
        let physical=nativeWidth*staging.width/fit.geometry.size.width+12
        return isPhone ? physical:max(physical,min(420,max(320,view.safeAreaLayoutGuide.layoutFrame.width*0.30)))
    }

    private var cardStride:CGFloat{cardWidth+22}
    private var positionKey=""
    private var selectingTheme=false,selectionIndex=0,selectionCards:[UIButton]=[],selectionPreviews:[SpatialPreview]=[]
    private var themeShelfTop:NSLayoutConstraint!
    private var model:DeviceModel = .nds,theme=0,items:[ROMItem]=[],current:ROMItem?,choosing=true,loading=false
    private var openingLink:CADisplayLink?,openingStart:CFTimeInterval=0
    private var mediaSeatFeedbackSent=false
    private var insertionLink:CADisplayLink?,insertionStart:CFTimeInterval=0,insertionGhost:UIImageView?,insertionFrom=CGRect.zero,insertionTo=CGRect.zero,insertionSlot=CGPoint.zero,pendingItem:ROMItem?
    #if DEBUG
    private var qaStarted=false,qaFrames=0,gowEvents=Set<Int>()
    private var inputChecks:[String:Bool]=[:],qaAnimationFrames=Set<String>()
    #endif
    private var portraitPlay=false,waitingForPortrait=false
    private var portraitSelection:(ROMItem,CartridgeView)?
    override var prefersStatusBarHidden:Bool{true}
    override var preferredScreenEdgesDeferringSystemGestures:UIRectEdge{[.bottom]}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {return portraitPlay && model == .gbc ? .portrait:.landscapeRight}
        return UIDevice.current.userInterfaceIdiom == .pad ? .all:.allButUpsideDown
    }
    private func updatePhoneOrientation(){guard UIDevice.current.userInterfaceIdiom == .phone else{return};setNeedsUpdateOfSupportedInterfaceOrientations();let mask:UIInterfaceOrientationMask=portraitPlay && model == .gbc ? .portrait:.landscapeRight;view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations:mask))}
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor=UIColor(hex:0x191E1D);setup();reload();showHome()}
    private func setup(){
        machine.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(machine);NSLayoutConstraint.activate([machine.leadingAnchor.constraint(equalTo:view.leadingAnchor),machine.trailingAnchor.constraint(equalTo:view.trailingAnchor),machine.topAnchor.constraint(equalTo:view.topAnchor),machine.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        nav.axis = .horizontal;nav.spacing=isPhone ? 6:12;nav.alignment = .center;nav.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(nav)
        titleButton.titleLabel?.font = .systemFont(ofSize:17,weight:.semibold);titleButton.contentHorizontalAlignment = .left;titleButton.heightAnchor.constraint(equalToConstant:44).isActive=true;titleButton.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);actions.setContentHuggingPriority(.required,for:.horizontal);titleButton.layer.cornerRadius=12;titleButton.tintColor=UIColor(hex:0xE4E6DE);titleButton.addTarget(self,action:#selector(titleTapped),for:.touchUpInside);nav.addArrangedSubview(titleButton)
        actions.axis = .horizontal;actions.spacing=isPhone ? 6:8;nav.addArrangedSubview(actions)
        NSLayoutConstraint.activate([nav.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:isPhone ? 12:24),nav.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:isPhone ? -12:-24),nav.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:isPhone ? 4:12),nav.heightAnchor.constraint(equalToConstant:isPhone ? 44:48)])
        pickerScroll.translatesAutoresizingMaskIntoConstraints=false;pickerContent.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(pickerScroll);pickerScroll.addSubview(pickerContent);pickerScroll.alwaysBounceVertical=false;pickerScroll.showsVerticalScrollIndicator=false
        home.axis = .vertical;home.spacing=18;home.translatesAutoresizingMaskIntoConstraints=false;pickerContent.addSubview(home)
        NSLayoutConstraint.activate([pickerScroll.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor),pickerScroll.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor),pickerScroll.topAnchor.constraint(equalTo:isPhone ? view.safeAreaLayoutGuide.topAnchor:nav.bottomAnchor,constant:12),pickerScroll.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-12),pickerContent.leadingAnchor.constraint(equalTo:pickerScroll.contentLayoutGuide.leadingAnchor),pickerContent.trailingAnchor.constraint(equalTo:pickerScroll.contentLayoutGuide.trailingAnchor),pickerContent.topAnchor.constraint(equalTo:pickerScroll.contentLayoutGuide.topAnchor),pickerContent.bottomAnchor.constraint(equalTo:pickerScroll.contentLayoutGuide.bottomAnchor),pickerContent.widthAnchor.constraint(equalTo:pickerScroll.frameLayoutGuide.widthAnchor),pickerContent.heightAnchor.constraint(greaterThanOrEqualTo:pickerScroll.frameLayoutGuide.heightAnchor),home.centerXAnchor.constraint(equalTo:pickerContent.centerXAnchor),home.centerYAnchor.constraint(equalTo:pickerContent.centerYAnchor),home.widthAnchor.constraint(lessThanOrEqualToConstant:900),home.leadingAnchor.constraint(greaterThanOrEqualTo:pickerContent.leadingAnchor,constant:24),home.trailingAnchor.constraint(lessThanOrEqualTo:pickerContent.trailingAnchor,constant:-24),home.topAnchor.constraint(greaterThanOrEqualTo:pickerContent.topAnchor,constant:16),home.bottomAnchor.constraint(lessThanOrEqualTo:pickerContent.bottomAnchor,constant:-16)])
        let compact=pickerContent.heightAnchor.constraint(equalTo:home.heightAnchor,constant:32);compact.priority = .defaultLow;compact.isActive=true
        shelf.translatesAutoresizingMaskIntoConstraints=false;shelf.showsHorizontalScrollIndicator=false;shelf.alwaysBounceHorizontal=true;shelf.isDirectionalLockEnabled=true;shelf.canCancelContentTouches=true;shelf.decelerationRate = .fast;shelf.delegate=self;shelf.contentInsetAdjustmentBehavior = .never;view.addSubview(shelf);cards.axis = .horizontal;cards.spacing=22;cards.translatesAutoresizingMaskIntoConstraints=false;shelf.addSubview(cards)
        shelfCenter=shelf.centerYAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerYAnchor,constant:isPhone ? -12:25);shelfHeight=shelf.heightAnchor.constraint(equalToConstant:320)
        NSLayoutConstraint.activate([shelf.leadingAnchor.constraint(equalTo:view.leadingAnchor),shelf.trailingAnchor.constraint(equalTo:view.trailingAnchor),shelfCenter,shelfHeight,cards.leadingAnchor.constraint(equalTo:shelf.contentLayoutGuide.leadingAnchor,constant:24),cards.trailingAnchor.constraint(equalTo:shelf.contentLayoutGuide.trailingAnchor,constant:-24),cards.topAnchor.constraint(equalTo:shelf.contentLayoutGuide.topAnchor),cards.bottomAnchor.constraint(equalTo:shelf.contentLayoutGuide.bottomAnchor),cards.heightAnchor.constraint(equalTo:shelf.frameLayoutGuide.heightAnchor)])
        emptyLabel.text="从“文件”添加 ROM，开始你的收藏。";emptyLabel.textColor = .lightGray;emptyLabel.font = .systemFont(ofSize:17);emptyLabel.textAlignment = .center;emptyLabel.numberOfLines=0;emptyLabel.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(emptyLabel);NSLayoutConstraint.activate([emptyLabel.centerXAnchor.constraint(equalTo:view.centerXAnchor),emptyLabel.topAnchor.constraint(equalTo:nav.bottomAnchor,constant:80),emptyLabel.widthAnchor.constraint(lessThanOrEqualTo:view.widthAnchor,multiplier:0.9)])
        busy.translatesAutoresizingMaskIntoConstraints=false;busy.color = .white;view.addSubview(busy);NSLayoutConstraint.activate([busy.centerXAnchor.constraint(equalTo:view.centerXAnchor),busy.centerYAnchor.constraint(equalTo:view.centerYAnchor)])
        setupThemeShelf()
        pages.translatesAutoresizingMaskIntoConstraints=false;pages.hidesForSinglePage=true;pages.allowsContinuousInteraction=true;pages.pageIndicatorTintColor=UIColor(hex:0x59635B);pages.currentPageIndicatorTintColor=UIColor(hex:0xE1C681);pages.accessibilityLabel="浏览项目";view.addSubview(pages)
        NSLayoutConstraint.activate([pages.centerXAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerXAnchor),pages.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor),pages.widthAnchor.constraint(lessThanOrEqualTo:view.safeAreaLayoutGuide.widthAnchor,constant:-40),pages.heightAnchor.constraint(equalToConstant:32)])
        pages.addTarget(self,action:#selector(pageChanged),for:.valueChanged)
        if isPhone{setupSideMenu()}
        machine.onButton={control,down in emu_button(Int32(control.rawValue),down ? 1:0)}
        machine.onAxis={x,y in emu_axis(0,0,Int32(x*32767));emu_axis(0,1,Int32(y*32767))}
        machine.onTouch={[weak self] u,v,down in guard let self else{return};let x=self.model == .n3ds ? (0.1+u*0.8)*65534-32767:u*65534-32767;emu_touch(Int32(x),Int32(v*32767),down ? 1:0)}
        machine.onUtility={[weak self] id in guard let self else{return};switch id {case 0:self.changeCartridge();case 1:self.session.volume=max(0,self.session.volume-0.1);case 2:self.session.volume=min(1,self.session.volume+0.1);case 3:self.session.volume=self.session.volume>0 ? 0:1;case 4:self.machine.screenBrightness=self.machine.screenBrightness>0.7 ? 0.55:1;default:break}}
        machine.onPower={[weak self] in self?.power()};session.onFrame={[weak self] image in self?.machine.frameImage=image}
    }
    private func setupThemeShelf(){
        themeHeading.textColor=UIColor(hex:0xEAE6D7);themeHeading.font = .systemFont(ofSize:24,weight:.semibold);themeHeading.textAlignment = .center;themeHeading.numberOfLines=2;themeHeading.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(themeHeading)
        showcaseLight.frame=view.bounds;showcaseLight.autoresizingMask=[.flexibleWidth,.flexibleHeight];view.addSubview(showcaseLight)
        themeShelf.translatesAutoresizingMaskIntoConstraints=false;themeShelf.showsHorizontalScrollIndicator=false;themeShelf.contentInsetAdjustmentBehavior = .never;themeShelf.decelerationRate = .normal;themeShelf.delaysContentTouches=false;themeShelf.delegate=self;themeShelf.alwaysBounceHorizontal=true;themeShelf.isDirectionalLockEnabled=true;view.addSubview(themeShelf)
        themeCards.axis = .horizontal;themeCards.spacing=24;themeCards.translatesAutoresizingMaskIntoConstraints=false;themeShelf.addSubview(themeCards)
        themeShelfTop=themeShelf.topAnchor.constraint(equalTo:themeHeading.bottomAnchor,constant:12)
        NSLayoutConstraint.activate([themeHeading.topAnchor.constraint(equalTo:isPhone ? view.safeAreaLayoutGuide.topAnchor:nav.bottomAnchor,constant:12),themeHeading.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:36),themeHeading.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-36),themeHeading.heightAnchor.constraint(equalToConstant:38),themeShelf.leadingAnchor.constraint(equalTo:view.leadingAnchor),themeShelf.trailingAnchor.constraint(equalTo:view.trailingAnchor),themeShelfTop,themeShelf.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-40),themeCards.leadingAnchor.constraint(equalTo:themeShelf.contentLayoutGuide.leadingAnchor),themeCards.trailingAnchor.constraint(equalTo:themeShelf.contentLayoutGuide.trailingAnchor),themeCards.topAnchor.constraint(equalTo:themeShelf.contentLayoutGuide.topAnchor),themeCards.bottomAnchor.constraint(equalTo:themeShelf.contentLayoutGuide.bottomAnchor),themeCards.heightAnchor.constraint(equalTo:themeShelf.frameLayoutGuide.heightAnchor)])
        homeBrand.axis = .vertical;homeBrand.alignment = .center;homeBrand.spacing=3;homeBrand.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(homeBrand)
        homeBrandName.font = .systemFont(ofSize:9,weight:.medium);homeBrandName.textColor=UIColor(hex:0xA6B2A5);homeBrandName.textAlignment = .center
        homeBrandLogo.contentMode = .scaleAspectFit;homeBrand.addArrangedSubview(homeBrandName);homeBrand.addArrangedSubview(homeBrandLogo)
        NSLayoutConstraint.activate([homeBrand.centerXAnchor.constraint(equalTo:themeHeading.centerXAnchor),homeBrand.topAnchor.constraint(equalTo:themeHeading.topAnchor),homeBrand.widthAnchor.constraint(equalToConstant:220),homeBrand.heightAnchor.constraint(equalTo:themeHeading.heightAnchor),homeBrandName.heightAnchor.constraint(equalToConstant:10),homeBrandLogo.widthAnchor.constraint(equalToConstant:220)])
        homeBrand.isHidden=true
        themeShelf.isHidden=true;themeHeading.isHidden=true
        themeShelf.panGestureRecognizer.maximumNumberOfTouches=1;shelf.panGestureRecognizer.maximumNumberOfTouches=1
    }
    private func setupSideMenu(){
        menuHandle.setImage(UIImage(systemName:"sidebar.left"),for:.normal);menuHandle.tintColor=UIColor(hex:0xB3C3AD);menuHandle.backgroundColor = .clear;menuHandle.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize:12,weight:.semibold),forImageIn:.normal);menuHandle.layer.cornerRadius=14;menuHandle.accessibilityLabel="展开菜单，也可向右滑动";menuHandle.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(menuHandle)
        NSLayoutConstraint.activate([menuHandle.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:2),menuHandle.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:8),menuHandle.widthAnchor.constraint(equalToConstant:44),menuHandle.heightAnchor.constraint(equalToConstant:44)])
        menuHandle.addAction(UIAction{[weak self] _ in self?.setMenu(open:true)},for:.touchUpInside)
        let reveal=UIPanGestureRecognizer(target:self,action:#selector(revealMenu(_:)));reveal.maximumNumberOfTouches=1;menuHandle.addGestureRecognizer(reveal)
        menuShade.backgroundColor=UIColor.black.withAlphaComponent(0.42);menuShade.translatesAutoresizingMaskIntoConstraints=false;menuShade.addAction(UIAction{[weak self] _ in self?.setMenu(open:false)},for:.touchUpInside);view.addSubview(menuShade)
        menuPanel.backgroundColor=UIColor(hex:0x25312B);menuPanel.layer.cornerRadius=24;menuPanel.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(menuPanel)
        let scroll=UIScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false;scroll.showsVerticalScrollIndicator=false;menuPanel.addSubview(scroll);menuRows.axis = .vertical;menuRows.spacing=10;menuRows.translatesAutoresizingMaskIntoConstraints=false;scroll.addSubview(menuRows)
        NSLayoutConstraint.activate([menuShade.leadingAnchor.constraint(equalTo:view.leadingAnchor),menuShade.trailingAnchor.constraint(equalTo:view.trailingAnchor),menuShade.topAnchor.constraint(equalTo:view.topAnchor),menuShade.bottomAnchor.constraint(equalTo:view.bottomAnchor),menuPanel.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:8),menuPanel.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:8),menuPanel.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-8),menuPanel.widthAnchor.constraint(equalToConstant:300),scroll.leadingAnchor.constraint(equalTo:menuPanel.leadingAnchor,constant:16),scroll.trailingAnchor.constraint(equalTo:menuPanel.trailingAnchor,constant:-16),scroll.topAnchor.constraint(equalTo:menuPanel.topAnchor,constant:16),scroll.bottomAnchor.constraint(equalTo:menuPanel.bottomAnchor,constant:-16),menuRows.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),menuRows.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),menuRows.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor),menuRows.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor),menuRows.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor)])
        let close=UISwipeGestureRecognizer(target:self,action:#selector(closeMenuGesture));close.direction = .left;menuPanel.addGestureRecognizer(close);menuShade.isHidden=true;menuPanel.isHidden=true
    }
    @objc private func revealMenu(_ gesture:UIPanGestureRecognizer){if gesture.translation(in:view).x>16{setMenu(open:true)}}
    @objc private func closeMenuGesture(){setMenu(open:false)}
    private func setMenu(open:Bool,animated:Bool=true){
        guard isPhone,open != menuOpen,(!open || !loading) else{return};machine.cancelTouches();menuOpen=open
        if open {
            menuPausedGame=session.running;if menuPausedGame{session.pause()};populateMenu();menuShade.isHidden=false;menuPanel.isHidden=false;view.bringSubviewToFront(menuShade);view.bringSubviewToFront(menuPanel);menuPanel.transform=CGAffineTransform(translationX:-320,y:0);menuShade.alpha=0
        }
        let changes={self.menuPanel.transform=open ? .identity:CGAffineTransform(translationX:-320,y:0);self.menuShade.alpha=open ? 1:0;self.menuHandle.alpha=open ? 0:1}
        let finish:(Bool)->Void={_ in if !open{self.menuShade.isHidden=true;self.menuPanel.isHidden=true;if self.menuPausedGame && self.session.running{self.session.resume()};self.menuPausedGame=false};UIAccessibility.post(notification:.screenChanged,argument:open ? self.menuRows:self.menuHandle)}
        if animated{UIView.animate(withDuration:0.24,delay:0,options:[.curveEaseOut],animations:changes,completion:finish)}else{changes();finish(true)}
    }
    private func populateMenu(){
        clear(menuRows)
        let heading=UILabel();heading.text=choosing ? (selectingTheme ? model.name:"菜单"):(model == .psp ? "PSP":model == .gba ? "GBA":model == .gbc ? "GBC":model.name)+" · "+model.themes[theme];heading.numberOfLines=0;heading.textColor=UIColor(hex:0xEAE6D7);heading.font = .systemFont(ofSize:19,weight:.semibold);let close=UIButton(type:.system);close.setImage(UIImage(systemName:"xmark"),for:.normal);close.tintColor=UIColor(hex:0xDDE7D6);close.accessibilityLabel="收起菜单";NSLayoutConstraint.activate([close.widthAnchor.constraint(equalToConstant:44),close.heightAnchor.constraint(equalToConstant:44)]);close.addAction(UIAction{[weak self] _ in self?.setMenu(open:false)},for:.touchUpInside);let header=UIStackView(arrangedSubviews:[heading,close]);header.axis = .horizontal;header.alignment = .center;heading.setContentCompressionResistancePriority(.required,for:.vertical);header.spacing=8;menuRows.addArrangedSubview(header)
        func item(_ title:String,_ symbol:String,_ action:@escaping(UIButton)->Void){let button=UIButton(type:.system);var config=UIButton.Configuration.filled();config.title=title;config.image=UIImage(systemName:symbol);config.imagePadding=12;config.baseBackgroundColor=UIColor(hex:0x344239);config.baseForegroundColor=UIColor(hex:0xE4E9DF);config.contentInsets=NSDirectionalEdgeInsets(top:14,leading:14,bottom:14,trailing:14);button.configuration=config;button.contentHorizontalAlignment = .left;button.heightAnchor.constraint(greaterThanOrEqualToConstant:50).isActive=true;button.addAction(UIAction{[weak self,weak button] _ in guard let self,let button else{return};self.setMenu(open:false,animated:false);action(button)},for:.touchUpInside);menuRows.addArrangedSubview(button)}
        if !choosing{item("选择掌机","rectangle.3.group"){[weak self] _ in self?.showSpatialSwitcher()};item("更换卡带","rectangle.stack"){[weak self] _ in self?.changeCartridge()}}
        else if selectingTheme{item("返回机型选择","chevron.left"){[weak self] _ in self?.showHome()}}
        item("添加 ROM","square.and.arrow.down"){[weak self] _ in self?.importROM()}
        if session.running{item("存下此刻","bookmark"){[weak self] _ in self?.instantState(false,slot:0)};item("恢复手动存档","arrow.uturn.backward"){[weak self] _ in self?.instantState(true,slot:0)};item("继续上次离开","play.circle"){[weak self] _ in self?.instantState(true,slot:1)}}
        if session.running{item("显示与触感","slider.horizontal.3"){[weak self] button in self?.positionPanel(button)}}
        if !choosing{item(session.running ? "保存并关机":"返回机型首页","power"){[weak self] _ in self?.power()}}
        item("收起菜单","chevron.left"){_ in}
    }
    private func updateThemeMetrics(){
        guard choosing else{return}
        themeCards.spacing=themeSpacing
        let safeWidth=min(themeShelf.bounds.width,view.safeAreaLayoutGuide.layoutFrame.width)
        let homeWidth=isPhone ? min(760,max(300,safeWidth*0.76)):max(540,safeWidth*0.90)
        let width=homeWidth,height=max(180,(themeShelf.bounds.height-16)*(isPhone ? 0.84:1))
        if abs(themeWidth-width)>0.5 || abs(themeHeight-height)>0.5 || abs(themeViewport-themeShelf.bounds.width)>0.5 {
            themeWidth=width;themeHeight=height;themeViewport=themeShelf.bounds.width
            for constraint in themeSizeConstraints{constraint.constant=constraint.firstAttribute == .width ? width:height}
            let inset=max(16,(themeShelf.bounds.width-width)/2);themeShelf.contentInset=UIEdgeInsets(top:0,left:inset,bottom:0,right:inset);themeShelf.contentOffset=CGPoint(x:CGFloat(selectionIndex)*(width+themeSpacing)-inset,y:0)
        }
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--validate-")}){UIApplication.shared.isIdleTimerDisabled=true}
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--validate-instant-core"),!qaStarted{qaStarted=true;validateInstantCore();return}
        if ProcessInfo.processInfo.arguments.contains("--validate-spatial-audit"),!qaStarted{qaStarted=true;validateSpatialAudit();return}
        if ProcessInfo.processInfo.arguments.contains("--validate-assembly"),!qaStarted {
            qaStarted=true
            let raw=ProcessInfo.processInfo.arguments.first{$0.hasPrefix("--qa-model=")}?.split(separator:"=").last.map(String.init) ?? "3ds"
            model=DeviceModel(rawValue:raw) ?? .n3ds;theme=0;showLibrary()
            DispatchQueue.main.asyncAfter(deadline:.now()+1.4){guard let card=self.cards.arrangedSubviews.first as? CartridgeView else{return};self.insert(card.item,from:card)};return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-phone-ui"),!qaStarted {qaStarted=true;validatePhoneUI();return}
        if ProcessInfo.processInfo.arguments.contains("--validate-library"),!qaStarted {qaStarted=true
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations:.landscapeLeft))
            DispatchQueue.main.asyncAfter(deadline:.now()+1){self.validateLibrary()};return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-position"),!qaStarted {qaStarted=true
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations:.landscapeLeft))
            DispatchQueue.main.asyncAfter(deadline:.now()+1){self.validatePositions()};return
        }
        if ProcessInfo.processInfo.arguments.contains("--import-library"),!qaStarted {qaStarted=true;importTransferredLibrary();return}
        if ProcessInfo.processInfo.arguments.contains("--validate-port"),!qaStarted {qaStarted=true
            if let scene=view.window?.windowScene{scene.requestGeometryUpdate(.iOS(interfaceOrientations:ProcessInfo.processInfo.arguments.contains("--landscape") ? .landscapeLeft:.portrait));DispatchQueue.main.asyncAfter(deadline:.now()+1){self.runPortValidation()}}else{runPortValidation()}
        }
        #endif
    }
    #if DEBUG
    private func validateInstantCore(){
        let fm=FileManager.default,qa=fm.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA")
        let rom=qa.appendingPathComponent("instant-probe.gba"),save=qa.appendingPathComponent("instant-"+UUID().uuidString)
        var result:[String:Any]=["isolated":true,"passed":false,"memoryType":"videoRAM"]
        do{
            try fm.createDirectory(at:save,withIntermediateDirectories:true)
            guard let core=Bundle.main.url(forResource:"mgba_libretro",withExtension:"dylib",subdirectory:"cores"),fm.fileExists(atPath:rom.path),emu_start(core.path,rom.path,save.path) != 0 else{throw LibraryError.unavailable("Original probe/core unavailable")}
            for _ in 0..<120{emu_run()};let before=emu_vram_hash();let stored=emu_state_save(0)
            emu_button(8,1);for _ in 0..<120{emu_run()};let changed=emu_vram_hash();let restored=emu_state_load(0);let after=emu_vram_hash();emu_stop()
            guard emu_start(core.path,rom.path,save.path) != 0 else{throw LibraryError.unavailable("Probe reload failed")}
            for _ in 0..<120{emu_run()};let automatic=emu_state_load(1);emu_stop()
            result["manualSave"]=stored;result["manualLoad"]=restored;result["autoLoad"]=automatic;result["memoryChanged"]=changed != before;result["memoryRestored"]=after==before;result["passed"]=stored==1 && restored==1 && automatic==1 && changed != before && after==before
        }catch{result["error"]=error.localizedDescription;emu_stop()}
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:qa.appendingPathComponent("instant-core-result.json"),options:.atomic)}
    }
    private func validateSpatialAudit(){
        let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA/SpatialAudit")
        try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
        let models=DeviceModel.available(onPhone:isPhone)
        let cases=models.flatMap{kind in (0..<kind.themes.count).map{(kind,$0,false)}}+models.map{($0,0,true)}
        var rows=[[String:Any]]()
        let overlay=UIView(frame:view.bounds);overlay.backgroundColor=view.backgroundColor;view.addSubview(overlay)
        func step(_ index:Int){
            guard index<cases.count else{if let bytes=try? JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]){try? bytes.write(to:qa.appendingPathComponent("checks.json"))};overlay.removeFromSuperview();self.showHome();return}
            let (kind,theme,media)=cases[index],name=kind.rawValue+(media ? "-media":"-theme-"+String(theme))
            let preview=media ? SpatialPreview(model:kind,cover:nil,tint:0x476A58):SpatialPreview(model:kind,theme:theme)
            preview.frame=self.view.safeAreaLayoutGuide.layoutFrame.insetBy(dx:28,dy:20);overlay.addSubview(preview);preview.setFocused(true);preview.layoutIfNeeded()
            func capture(_ label:String){let image=UIGraphicsImageRenderer(size:self.view.bounds.size).image{context in overlay.backgroundColor?.setFill();context.fill(self.view.bounds);preview.snapshot().draw(in:preview.frame)};try? image.pngData()?.write(to:qa.appendingPathComponent(name+"-"+label+".png"))}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
                let before=preview.inspectionDiagnostics["cameraScale"] as? Double ?? 0
                capture("rest");preview.inspect(yaw:1.1,pitch:0.60);preview.setNeedsLayout();preview.layoutIfNeeded()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3){
                    capture("rotated");var state=preview.inspectionDiagnostics
                    state["model"]=kind.rawValue;state["theme"]=theme;state["media"]=media;state["rotationApplied"]=abs(state["yaw"] as? Double ?? 0)>0.5
                    state["cameraReservesRotationSpace"]=(state["cameraScale"] as? Double ?? 0)>=before-0.001
                    preview.endInspection()
                    DispatchQueue.main.asyncAfter(deadline:.now()+1.8){
                        state["settledYaw"]=preview.inspectionDiagnostics["yaw"]
                        state["settled"]=abs(preview.inspectionDiagnostics["yaw"] as? Double ?? 1)<0.075
                        state["viewport"]=[Double(self.view.bounds.width),Double(self.view.bounds.height)]
                        #if targetEnvironment(simulator)
                        state["environment"]="simulator"
                        #else
                        state["environment"]="physical-device"
                        #endif
                        rows.append(state);preview.setPreviewActive(false);preview.removeFromSuperview();step(index+1)
                    }
                }
            }
        };step(0)
    }
    private func validateWheel(){
        let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA/Wheel")
        try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
        showSpatialSwitcher()
        guard let controller=presentedViewController as? SpatialSwitchController else{return}
        let initialFrames=emu_frames(),initialModel=model
        var result:[String:Any]=["initialModel":model.rawValue,"focusedCurrent":controller.wheel.entries[controller.wheel.selectedIndex].model==model.rawValue]
        controller.wheel.select(controller.wheel.entries.count-1)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.8){
            result["pausedWhileBrowsing"]=emu_frames()==initialFrames
            result["browseDoesNotSwitch"]=self.model==initialModel && self.session.running
            result["geometry"]=controller.wheel.diagnostics
            let shot=UIGraphicsImageRenderer(size:self.view.bounds.size).image{_ in self.view.window?.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? shot.pngData()?.write(to:qa.appendingPathComponent("wheel.png"))
            try? controller.wheel.sceneSnapshot().pngData()?.write(to:qa.appendingPathComponent("wheel-scene.png"))
            if ProcessInfo.processInfo.arguments.contains("--qa-hold-wheel"){return}
            controller.cancelSelection{
                DispatchQueue.main.asyncAfter(deadline:.now()+0.4){
                    result["cancelResumes"]=self.session.running && self.model==initialModel && emu_frames()>initialFrames
                    self.showSpatialSwitcher{next in
                    let destination=next.wheel.entries.firstIndex{$0.model != self.model.rawValue} ?? 0
                    next.wheel.select(destination);next.commitSelection()
                    DispatchQueue.main.asyncAfter(deadline:.now()+1.5){
                        result["confirmSwitches"]=self.model.rawValue==next.wheel.entries[destination].model && self.choosing && self.selectingTheme && !self.session.running
                        result["finalModel"]=self.model.rawValue;result["selectingTheme"]=self.selectingTheme;result["running"]=self.session.running
                        result["inputsReleased"]=emu_input_mask()==0 && emu_axis_value(0)==0 && emu_axis_value(1)==0
                        if let bytes=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? bytes.write(to:qa.appendingPathComponent("result.json"))}
                        self.showHome()
                    }
                    }
                }
            }
        }
    }
    private func validatePhoneUI(){
        let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA/PhoneUI")
        try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
        var rows:[[String:Any]]=[]
        let cases:[(String,()->Void)]=[("home",{self.showHome()})]+DeviceModel.available(onPhone:isPhone).flatMap{kind in
            (0..<kind.themes.count).map{theme in (kind.rawValue+"-theme-"+String(theme),{self.showThemes(kind);self.selectionIndex=theme;self.updateSelection()})}+[(kind.rawValue+"-library",{self.model=kind;self.theme=0;self.showLibrary()})]
        }
        func step(_ index:Int){
            guard index<cases.count else{if let data=try? JSONSerialization.data(withJSONObject:rows,options:.prettyPrinted){try? data.write(to:qa.appendingPathComponent("checks.json"))};self.model = .psp;self.theme=0;self.showLibrary();self.setMenu(open:true)
                DispatchQueue.main.asyncAfter(deadline:.now()+0.4){let image=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? image.pngData()?.write(to:qa.appendingPathComponent("side-menu.png"));let state:[String:Any]=["menuOpen":self.menuOpen,"topToolbarHidden":self.nav.isHidden,"handleFrame":[self.menuHandle.frame.minX,self.menuHandle.frame.minY,self.menuHandle.frame.width,self.menuHandle.frame.height],"viewport":[self.view.bounds.width,self.view.bounds.height]];if let data=try? JSONSerialization.data(withJSONObject:state,options:.prettyPrinted){try? data.write(to:qa.appendingPathComponent("side-menu.json"))};self.setMenu(open:false,animated:false);self.showHome()};return}
            let (name,action)=cases[index];action()
            DispatchQueue.main.asyncAfter(deadline:.now()+1.2){
                self.view.layoutIfNeeded()
                let image=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in
                    self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)
                    if self.choosing{self.showcaseLight.snapshot().draw(in:self.view.bounds)}
                    if self.choosing{for preview in self.selectionPreviews where preview.convert(preview.bounds,to:self.view).intersects(self.view.bounds){preview.snapshot().draw(in:preview.convert(preview.bounds,to:self.view))}}
                    // SceneKit snapshots are composited after UIKit; restore native captions above that pass.
                    if self.choosing && self.selectingTheme{for card in self.selectionCards{if let label=(card as? ShowcaseSelectionCard)?.caption,label.convert(label.bounds,to:self.view).intersects(self.view.bounds){label.drawHierarchy(in:label.convert(label.bounds,to:self.view),afterScreenUpdates:true)}}}
                    else{for case let card as CartridgeView in self.cards.arrangedSubviews{card.drawSpatialSnapshot(in:self.view)}}
                }
                try? image.pngData()?.write(to:qa.appendingPathComponent(name+".png"))
                var clipped:[String]=[]
                for card in self.choosing ? Array(self.selectionCards.dropFirst(self.selectionIndex).prefix(1)):[] {
                    let frame=card.convert(card.bounds,to:self.view)
                    if !self.view.safeAreaLayoutGuide.layoutFrame.contains(frame){clipped.append(card.accessibilityLabel ?? "card")}
                }
                let neighbours=self.selectionPreviews.enumerated().filter{i,p in i != self.selectionIndex && p.convert(p.projectedSolidBounds,to:self.view).intersection(self.view.bounds).width>16}.count
                let focusHit:Bool
                if self.choosing,self.selectionCards.indices.contains(self.selectionIndex){let card=self.selectionCards[self.selectionIndex],point=card.convert(CGPoint(x:card.bounds.midX,y:card.bounds.midY),to:self.view);focusHit=self.view.hitTest(point,with:nil)===card}else{focusHit=true}
                rows.append(["visibleUnfocusedMachines":neighbours,"focusedCardReceivesTap":focusHit,"themeLabelsFit":!self.choosing || !self.selectingTheme || (self.view.safeAreaLayoutGuide.layoutFrame.contains(self.themeHeading.frame) && self.themeHeading.sizeThatFits(CGSize(width:self.themeHeading.bounds.width,height:100)).height<=self.themeHeading.bounds.height+0.5),"fullViewportLight":!self.choosing || self.showcaseLight.frame==self.view.bounds,"page":name,"width":self.view.bounds.width,"height":self.view.bounds.height,"cards":self.choosing ? self.selectionCards.count:self.cards.arrangedSubviews.count,"cardsOutsideSafeArea":clipped,"toolbarFits":self.actions.frame.maxX<=self.nav.bounds.width+1,"scrollIndicatorHidden":!self.shelf.showsHorizontalScrollIndicator,"cardPageHasNoMachine":self.choosing || self.machine.isHidden,"spatialAvailable":self.machine.spatial.available,"metadataFits":self.choosing || self.cards.arrangedSubviews.compactMap{$0 as? CartridgeView}.allSatisfy{$0.metadataFits},"focusedPreview":self.choosing && self.selectionPreviews.indices.contains(self.selectionIndex) ? self.selectionPreviews[self.selectionIndex].inspectionDiagnostics:[:]])
                step(index+1)
            }
        };step(0)
    }
    private func validateLibrary(){
        let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA/Library")
        try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
        var cases:[(DeviceModel,Int,CGFloat)]=[]
        for m in DeviceModel.allCases {for theme in 0..<m.themes.count {cases.append((m,theme,0))}}
        for m in [DeviceModel.nds,.n3ds] {for open in [CGFloat(0.2),0.5,0.8,1] {cases.append((m,0,open))}}
        var rows:[[String:Any]]=[]
        func step(_ i:Int){
            guard i<cases.count else{if let data=try? JSONSerialization.data(withJSONObject:rows,options:.prettyPrinted){try? data.write(to:qa.appendingPathComponent("checks.json"))};self.showHome();return}
            let (m,t,o)=cases[i];self.model=m;self.theme=t;self.showLibrary();self.machine.openness=o
            self.view.layoutIfNeeded()
            if o==0,self.cards.arrangedSubviews.count>1,self.shelf.contentSize.width>self.shelf.bounds.width {self.shelf.setContentOffset(CGPoint(x:self.cardStride-self.shelf.contentInset.left,y:0),animated:false)}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2){
                let image=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)}
                try? image.pngData()?.write(to:qa.appendingPathComponent(m.rawValue+"-"+String(t)+"-"+String(Int(o*100))+".png"))
                let scrollable=self.shelf.contentSize.width+self.shelf.contentInset.left+self.shelf.contentInset.right>self.shelf.bounds.width
                let overflow=self.shelf.contentSize.width>self.shelf.bounds.width
                let selected=self.cards.arrangedSubviews.count>1 ? self.cards.arrangedSubviews[1]:nil
                let centered:Bool
                if overflow {centered=selected.map{abs($0.convert(CGPoint(x:$0.bounds.midX,y:$0.bounds.midY),to:self.shelf).x-self.shelf.bounds.midX)<1} ?? true}
                else {centered=abs(self.cards.convert(CGPoint(x:self.cards.bounds.midX,y:self.cards.bounds.midY),to:self.shelf).x-self.shelf.bounds.midX)<1}
                let slot=CartridgeSlot.load(m)
                rows.append(["model":m.rawValue,"theme":t,"openness":o,"overflow":overflow,"scrollable":scrollable,"centered":centered,"scrollIndicator":self.shelf.showsHorizontalScrollIndicator,"slotWidth":slot?.width ?? 0,"cardWidth":slot?.cardWidth ?? 0,"outerAsset":MachineCanvas.skin(m,t,"outer") != nil])
                step(i+1)
            }
        };step(0)
    }
    private func validatePositions(){
        let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA/Position")
        try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
        let cases:[(DeviceModel,CGFloat)]=DeviceModel.allCases.flatMap{m in ([0,0.86,1] as [CGFloat]).map{(m,$0)}}
        var rows:[[String:Any]]=[]
        func step(_ i:Int){
            guard i<cases.count else {
                if let data=try? JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:qa.appendingPathComponent("positions.json"))}
                self.showThemes(.psp);self.view.layoutIfNeeded()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3){
                    let shot=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? shot.pngData()?.write(to:qa.appendingPathComponent("themes-centered.png"))
                    self.showHome();self.view.layoutIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.3){let home=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? home.pngData()?.write(to:qa.appendingPathComponent("models-centered.png"))}
                };return
            }
            let (m,v)=cases[i];self.model=m;self.theme=0;self.showLibrary();self.machine.isHidden=false;self.themeHeading.isHidden=true;self.machine.libraryMode=false;self.shelf.isHidden=true;self.machine.openness=1;self.machine.verticalPosition=v;self.view.layoutIfNeeded()
            DispatchQueue.main.asyncAfter(deadline:.now()+0.15){
                let layout=self.machine.layout
                var hits=true
                for (control,r) in layout.geometry.controls {
                    let local=CGPoint(x:r.midX,y:r.midY),screen=self.machine.pointForLocal(local)
                    let back=self.machine.localPointForValidation(screen)
                    var router=TouchInputRouter()
                    if !router.update(finger:1,point:back,ending:false,geometry:layout.geometry,enabled:true,scale:layout.scale).contains(.button(control,true)){hits=false}
                }
                rows.append(["model":m.rawValue,"position":v,"frame":[layout.frame.minX,layout.frame.minY,layout.frame.width,layout.frame.height],"viewport":[self.view.bounds.width,self.view.bounds.height],"controlsHit":hits,"withinScreen":layout.frame.minY>=self.view.safeAreaInsets.top+64 && layout.frame.maxY<=self.view.bounds.height-self.view.safeAreaInsets.bottom-19])
                let shot=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)}
                try? shot.pngData()?.write(to:qa.appendingPathComponent(m.rawValue+"-"+String(Int(v*100))+".png"));step(i+1)
            }
        }
        step(0)
    }
    private func importTransferredLibrary(){
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let incoming=documents.appendingPathComponent("Incoming",isDirectory:true)
        let urls=(FileManager.default.enumerator(at:incoming,includingPropertiesForKeys:nil)?.allObjects as? [URL] ?? []).filter{DeviceModel.detect(extension:$0.pathExtension) != nil || $0.pathExtension.lowercased()=="zip"}.sorted{$0.path<$1.path}
        loading=true;busy.startAnimating();UIApplication.shared.isIdleTimerDisabled=true
        library.importFiles(urls){[weak self] summary in guard let self else{return}
            self.loading=false;self.busy.stopAnimating();UIApplication.shared.isIdleTimerDisabled=false;self.items=self.library.load();self.showHome()
            let report:[String:Any]=["sourceFiles":urls.count,"added":summary.added.count,"duplicates":summary.duplicateCount,"failures":summary.failures,"total":self.items.count,"models":Dictionary(grouping:self.items,by:{$0.model.rawValue}).mapValues{$0.count}]
            if let data=try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted){try? data.write(to:documents.appendingPathComponent("import-report.json"),options:.atomic)}
            // Only staging copies are removed after the managed library commit succeeds.
            if summary.failures.isEmpty {try? FileManager.default.removeItem(at:incoming)}
            for item in self.items {self.covers.load(item){}}
        }
    }
    private func runPortValidation(){
        let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA")
        try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
        let selected=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--qa-model=")}).flatMap{DeviceModel(rawValue:String($0.dropFirst(11)))}
        let title=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--qa-title=")}).map{String($0.dropFirst(11))}
        let existing=selected.flatMap{kind in library.load().first(where:{$0.model==kind && (title==nil || $0.title.contains(title!))})}.map{library.romURL($0)}
        guard let input=existing ?? (try? FileManager.default.contentsOfDirectory(at:qa,includingPropertiesForKeys:nil))?.first(where:{DeviceModel.detect(extension:$0.pathExtension) != nil}) else{return}
        library.importFiles([input]){[weak self] summary in guard let self else{return}
            guard let item=summary.added.first ?? self.library.load().first(where:{self.library.romURL($0)==input || $0.title==cleanGameTitle(input.lastPathComponent)}) else{try? Data(summary.failures.joined(separator:"\n").utf8).write(to:qa.appendingPathComponent("error.txt"));return}
            self.model=item.model;self.portraitPlay=item.model == .gbc;self.theme=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--qa-theme=")}).flatMap{Int($0.dropFirst(11))}.map{max(0,min(self.model.themes.count-1,$0))} ?? 0;self.items=self.library.load();self.choosing=false;self.showLibrary()
            do {try self.session.start(item,library:self.library);self.current=item;self.machine.isHidden=false;self.themeHeading.isHidden=true;self.machine.libraryMode=false;self.machine.playing=true;self.machine.openness=1;self.machine.bookMode=ProcessInfo.processInfo.arguments.contains("--book");self.shelf.isHidden=true;self.emptyLabel.isHidden=true;self.toolbar()
                if ProcessInfo.processInfo.arguments.contains("--profile-performance"){
                    let seconds=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--profile-seconds=")}).flatMap{Double($0.dropFirst(18))} ?? 90
                    if ProcessInfo.processInfo.arguments.contains("--profile-core-only"){self.machine.spatial.isHidden=true;self.machine.spatial.isPlaying=false;self.machine.spatial.rendersContinuously=false}
                    DispatchQueue.main.asyncAfter(deadline:.now()+seconds){[weak self] in guard let self,self.session.running else{return};self.session.pause()
                        let state:[String:Any]=["game":item.title,"frames":emu_frames(),"model":item.model.rawValue,"coreOnly":ProcessInfo.processInfo.arguments.contains("--profile-core-only"),"timestamp":Date().timeIntervalSince1970]
                        if let data=try? JSONSerialization.data(withJSONObject:state,options:.prettyPrinted){try? data.write(to:qa.appendingPathComponent("performance-scene.json"))}
                        let screenshot=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? screenshot.pngData()?.write(to:qa.appendingPathComponent("performance-scene.png"))
                    }
                }
                self.session.onFrame={[weak self] image in guard let self else{return};if !ProcessInfo.processInfo.arguments.contains("--profile-core-only"){self.machine.frameImage=image};self.qaFrames+=1
                    if ProcessInfo.processInfo.arguments.contains("--validate-animation"),self.qaFrames==480 {
                        let image=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? image.pngData()?.write(to:qa.appendingPathComponent("after-insertion-boot.png"))
                        let state:[String:Any]=["frames":emu_frames(),"openness":self.machine.openness,"running":self.session.running,"model":self.model.rawValue,"haptics":PhoneHaptics.counts,"hapticsEnabled":PhoneHaptics.enabled]
                        if let data=try? JSONSerialization.data(withJSONObject:state,options:.prettyPrinted){try? data.write(to:qa.appendingPathComponent("after-insertion-boot.json"))}
                    }
                    if ProcessInfo.processInfo.arguments.contains("--validate-input"){self.validateInputsFrame()}
                    if ProcessInfo.processInfo.arguments.contains("--gta-playcheck"){self.advanceGTAFrame(qa:qa)}
                    if ProcessInfo.processInfo.arguments.contains("--gow-new-game"),let r=self.machine.activeGeometry.controls[.b]{
                        let frame=Int(emu_frames());self.session.performanceStage=frame<1200 ? "boot-menu":frame<1448 ? "new-game-selection":"opening-movie"
                        for event in [1200,1208,1320,1328,1440,1448] where frame>=event && !self.gowEvents.contains(event){self.gowEvents.insert(event);if event%120==0{self.machine.route(finger:928,point:self.machine.pointForLocal(CGPoint(x:r.midX,y:r.midY)))}else{self.machine.route(finger:928,point:.zero,ending:true)}}
                    }
                    if self.qaFrames==(ProcessInfo.processInfo.arguments.contains("--profile-performance") ? 12000:ProcessInfo.processInfo.arguments.contains("--gta-playcheck") ? 2400:ProcessInfo.processInfo.arguments.contains("--validate-input") ? 360:120) {
                        let screenshot=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)}
                        try? screenshot.pngData()?.write(to:qa.appendingPathComponent("screen.png"))
                        let state:[String:Any]=["frames":emu_frames(),"audioSamples":emu_audio_samples(),"width":emu_width(),"height":emu_height(),"model":item.model.rawValue,"boundsWidth":self.view.bounds.width,"boundsHeight":self.view.bounds.height,"sha256":item.id,"importFailures":summary.failures,"backend":String(cString:emu_backend()),"inputChecks":self.inputChecks,"released":emu_input_mask()==0 && emu_axis_value(0)==0 && emu_axis_value(1)==0,"haptics":PhoneHaptics.counts,"hapticsEnabled":PhoneHaptics.enabled]
                        if let data=try? JSONSerialization.data(withJSONObject:state,options:.prettyPrinted){try? data.write(to:qa.appendingPathComponent("result.json"))}
                        if ProcessInfo.processInfo.arguments.contains("--validate-wheel"){self.validateWheel();return}
                        self.session.pause()
                        if ProcessInfo.processInfo.arguments.contains("--validate-settings"),let button=self.actions.arrangedSubviews.first(where:{$0.accessibilityLabel=="显示调整"}) as? UIButton {
                            self.positionPanel(button)
                            DispatchQueue.main.asyncAfter(deadline:.now()+0.8){let image=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.window?.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? image.pngData()?.write(to:qa.appendingPathComponent("settings.png"))};return
                        }
                        self.changeCartridge();self.view.layoutIfNeeded()
                        let libraryScreen=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? libraryScreen.pngData()?.write(to:qa.appendingPathComponent("library.png"))
                        self.showThemes(self.model);self.view.layoutIfNeeded()
                        let themesScreen=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? themesScreen.pngData()?.write(to:qa.appendingPathComponent("themes.png"))
                        self.showHome();self.view.layoutIfNeeded()
                        let homeScreen=UIGraphicsImageRenderer(bounds:self.view.bounds).image{_ in self.view.drawHierarchy(in:self.view.bounds,afterScreenUpdates:true)};try? homeScreen.pngData()?.write(to:qa.appendingPathComponent("home.png"))
                        if ProcessInfo.processInfo.arguments.contains("--validate-animation"){self.showLibrary();self.view.layoutIfNeeded();DispatchQueue.main.asyncAfter(deadline:.now()+0.3){if let card=self.cards.arrangedSubviews.compactMap({$0 as? CartridgeView}).first(where:{$0.item.id==item.id}){self.insert(item,from:card)}}}
                    }
                }
            }catch{try? Data(error.localizedDescription.utf8).write(to:qa.appendingPathComponent("error.txt"))}
        }
    }
    private func captureAnimation(_ stage:String,_ progress:CGFloat){
        let captureStart=CACurrentMediaTime();defer{let cost=CACurrentMediaTime()-captureStart;if stage=="insert"{insertionStart+=cost}else{openingStart+=cost}}
        guard ProcessInfo.processInfo.arguments.contains("--validate-animation") else{return}
        let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA")
        for (index,value) in [CGFloat(0.18),0.42,0.66,0.90].enumerated(){let key=stage+"-"+String(index);if progress>=value,!qaAnimationFrames.contains(key){qaAnimationFrames.insert(key);let sceneImage=machine.spatial.available ? machine.spatial.snapshot():nil;let image=UIGraphicsImageRenderer(bounds:view.bounds).image{_ in view.drawHierarchy(in:view.bounds,afterScreenUpdates:true);sceneImage?.draw(in:machine.spatial.convert(machine.spatial.bounds,to:view))};try? image.pngData()?.write(to:qa.appendingPathComponent("animation-"+key+".png"));var state=machine.spatial.mediaDiagnostics;state["stage"]=stage;state["model"]=model.rawValue;state["sourceWidth"]=Double(insertionFrom.width);state["alignedWidth"]=Double(insertionTo.width);state["mediaScaleDelta"]=Double(abs(insertionFrom.width-insertionTo.width)/max(1,insertionTo.width));state["progress"]=Double(progress);state["viewport"]=[Double(view.bounds.width),Double(view.bounds.height)];if let bytes=try? JSONSerialization.data(withJSONObject:state,options:.prettyPrinted){try? bytes.write(to:qa.appendingPathComponent("animation-"+key+".json"))}}}
    }
    private func advanceGTAFrame(qa:URL){
        let g=machine.activeGeometry,phase=qaFrames%120
        if qaFrames<1800 {
            if let r=g.controls[.start],phase==30 || phase==39 {machine.route(finger:920,point:machine.pointForLocal(CGPoint(x:r.midX,y:r.midY)),ending:phase==39)}
            if let r=g.controls[.b],phase==60 || phase==69 {machine.route(finger:921,point:machine.pointForLocal(CGPoint(x:r.midX,y:r.midY)),ending:phase==69)}
        }
        if let r=g.stick,qaFrames==1900 || qaFrames==1960 {if qaFrames==1900 {machine.route(finger:922,point:machine.pointForLocal(CGPoint(x:r.midX,y:r.midY)));machine.route(finger:922,point:machine.pointForLocal(CGPoint(x:r.maxX,y:r.midY)))}else{machine.route(finger:922,point:.zero,ending:true)}}
        if !ProcessInfo.processInfo.arguments.contains("--profile-performance"),[600,1200,1800,1900,1960,2400].contains(qaFrames){let image=UIGraphicsImageRenderer(bounds:view.bounds).image{_ in view.drawHierarchy(in:view.bounds,afterScreenUpdates:true)};try? image.pngData()?.write(to:qa.appendingPathComponent("gta-\(qaFrames).png"))}
    }
    private func validateInputsFrame(){
        let g=machine.activeGeometry,keys=g.controls.keys.sorted{$0.rawValue<$1.rawValue}
        let step=(qaFrames-20)/14,phase=(qaFrames-20)%14
        guard qaFrames>=20,step>=0 else{return}
        if step<keys.count,let r=g.controls[keys[step]] {
            let point=CGPoint(x:r.midX,y:r.midY)
            if phase==0{machine.route(finger:910,point:machine.pointForLocal(point))}
            if phase==4{let before=PhoneHaptics.counts;machine.route(finger:910,point:machine.pointForLocal(point));inputChecks["held_feedback_"+keys[step].title]=PhoneHaptics.counts==before
                let qa=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("QA")
                let image=UIGraphicsImageRenderer(bounds:view.bounds).image{_ in view.drawHierarchy(in:view.bounds,afterScreenUpdates:true)}
                try? image.pngData()?.write(to:qa.appendingPathComponent("key-"+String(keys[step].rawValue)+".png"))
                if let data=try? JSONSerialization.data(withJSONObject:machine.mechanicalState,options:.prettyPrinted){try? data.write(to:qa.appendingPathComponent("key-"+String(keys[step].rawValue)+".json"))}
            }
            if phase==9{machine.route(finger:910,point:machine.pointForLocal(point),ending:true);inputChecks["button_"+keys[step].title]=emu_input_reads(Int32(keys[step].rawValue))>0}
        }else if step==keys.count,let r=g.stick {
            if phase==0{machine.route(finger:911,point:machine.pointForLocal(CGPoint(x:r.midX,y:r.midY)));machine.route(finger:911,point:machine.pointForLocal(CGPoint(x:r.maxX,y:r.maxY)))}
            if phase==9{machine.route(finger:911,point:.zero,ending:true);inputChecks["analog_x"]=emu_axis_reads(0)>0;inputChecks["analog_y"]=emu_axis_reads(1)>0}
        }else if step==keys.count+1,g.screens.count==2,let r=g.screens.last {
            if phase==0{machine.route(finger:912,point:machine.pointForLocal(CGPoint(x:r.midX,y:r.midY)))}
            if phase==9{machine.route(finger:912,point:.zero,ending:true);inputChecks["touchscreen"]=emu_pointer_reads()>0}
        }
    }
    #endif
    private func reload(){items=library.load();if !choosing && !loading{showLibrary()}}
    private func clear(_ stack:UIStackView){if stack===home{for c in stack.constraints where c.firstAttribute == .width && c.secondItem == nil {c.isActive=false}};for v in stack.arrangedSubviews{stack.removeArrangedSubview(v);v.removeFromSuperview()}}
    @objc private func pageChanged(){
        if choosing{selectionIndex=pages.currentPage;updateSelection()}
        else if !shelf.isHidden,cards.arrangedSubviews.indices.contains(pages.currentPage){explicitCardPage=pages.currentPage;let card=cards.arrangedSubviews[pages.currentPage];let x=card.frame.midX-shelf.bounds.width/2;let low = -shelf.contentInset.left,high=max(low,shelf.contentSize.width-shelf.bounds.width+shelf.contentInset.right);shelf.setContentOffset(CGPoint(x:max(low,min(high,x)),y:0),animated:true)}
    }
    private func syncPreviewActivity(){
        for (i,preview) in selectionPreviews.enumerated(){preview.setPreviewActive(choosing && !themeShelf.isHidden && abs(i-selectionIndex)<=1)}
        updateCardVisibility()
        machine.spatial.isPlaying = !machine.isHidden;machine.spatial.rendersContinuously = !machine.isHidden;machine.spatial.scene?.isPaused=machine.isHidden
        pages.isHidden=loading || session.running || (!choosing && shelf.isHidden)
        if choosing{pages.numberOfPages=selectionCards.count;pages.currentPage=selectionIndex}
    }
    private func toolbar(){
        syncPreviewActivity()
        if isPhone{nav.isHidden=true;menuHandle.isHidden=loading}
        titleButton.isHidden=choosing && !selectingTheme;titleButton.backgroundColor=choosing ? UIColor(hex:0x2D3931):.clear
        clear(actions)
        let titleFontSize:CGFloat=isPhone ? 14:17
        let modelTitle=isPhone ? (model == .gba ? "GBA":model == .gbc ? "GBC":"PSP"):model.name
        var titleConfig=UIButton.Configuration.plain();titleConfig.title=choosing ? (selectingTheme ? "‹  选择机型":""):"‹  \(modelTitle) · \(model.themes[theme])";titleConfig.baseForegroundColor=UIColor(hex:0xE4E6DE);titleConfig.contentInsets=NSDirectionalEdgeInsets(top:4,leading:10,bottom:4,trailing:10);titleConfig.titleLineBreakMode = .byTruncatingTail;titleConfig.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{attributes in var result=attributes;result.font = .systemFont(ofSize:titleFontSize,weight:.semibold);return result};titleButton.configuration=titleConfig
        if !choosing{button("rectangle.stack",label:"更换卡带",action:#selector(changeCartridge));button("square.and.arrow.down",label:"添加 ROM",action:#selector(importROM));if model == .nds{button(machine.bookMode ? "rectangle.portrait.rotate":"rectangle.landscape.rotate",label:"切换书本握法",action:#selector(toggleBook))};if session.running{button("bookmark",label:"即时存档",action:#selector(instantStateMenu));button("slider.horizontal.3",label:"显示调整",action:#selector(positionPanel(_:)))};button("power",label:session.running ? "保存并关机":"选择机型",action:#selector(power))}
    }
    private func button(_ symbol:String,label:String,action:Selector){let b=UIButton(type:.system);var config=UIButton.Configuration.filled();config.baseBackgroundColor=UIColor(hex:0x2E3933);config.baseForegroundColor=UIColor(hex:0xDFE6DC);config.image=UIImage(systemName:symbol);config.cornerStyle = .medium;b.configuration=config;b.accessibilityLabel=label;b.addTarget(self,action:action,for:.touchUpInside);NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant:isPhone ? 44:48),b.heightAnchor.constraint(equalToConstant:isPhone ? 44:48)]);actions.addArrangedSubview(b)}
    private func modelSketch(_ kind:DeviceModel)->UIImage {
        let size=CGSize(width:184,height:108),g=DeviceGeometry.make(kind)
        return UIGraphicsImageRenderer(size:size).image{ context in
            let c=context.cgContext,scale=min(170/g.size.width,70/g.size.height)
            c.saveGState();c.translateBy(x:(184-g.size.width*scale)/2,y:0);c.scaleBy(x:scale,y:scale);c.setStrokeColor(UIColor(hex:0xB6C3AD).cgColor);c.setLineWidth(1.3/scale)
            for r in g.shells{c.addPath(UIBezierPath(roundedRect:r,cornerRadius:24).cgPath);c.strokePath()};for r in g.screens{c.stroke(r)};for (_,r) in g.controls{c.addPath(UIBezierPath(roundedRect:r,cornerRadius:8).cgPath);c.strokePath()};c.restoreGState()
            UIImage(named:kind.rawValue+"-mark")?.drawAspectFit(in:CGRect(x:12,y:79,width:160,height:26))
        }
    }
    private func phoneCard(title:String,image:UIImage,horizontal:Bool)->UIButton {
        let card=UIButton(type:.system);card.backgroundColor=UIColor(hex:0x27322C);card.layer.cornerRadius=22
        card.accessibilityLabel=title;card.isAccessibilityElement=true
        let art=UIImageView(image:image);art.contentMode = .scaleAspectFit;art.isUserInteractionEnabled=false
        let label=UILabel();label.text=title;label.font = .systemFont(ofSize:16,weight:.semibold);label.textColor=UIColor(hex:0xDCE3D7);label.numberOfLines=2;label.textAlignment=horizontal ? .left:.center
        let stack=UIStackView(arrangedSubviews:[art,label]);stack.axis=horizontal ? .horizontal:.vertical;stack.spacing=horizontal ? 18:8;stack.alignment = .center;stack.isUserInteractionEnabled=false;stack.translatesAutoresizingMaskIntoConstraints=false;card.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:card.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:card.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:card.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:card.bottomAnchor,constant:-12),card.heightAnchor.constraint(equalToConstant:horizontal ? 120:164)])
        if horizontal {NSLayoutConstraint.activate([art.widthAnchor.constraint(equalToConstant:122),art.heightAnchor.constraint(equalToConstant:92)]);label.setContentHuggingPriority(.defaultLow,for:.horizontal)}
        else {NSLayoutConstraint.activate([art.heightAnchor.constraint(equalToConstant:94),art.widthAnchor.constraint(equalTo:stack.widthAnchor),label.widthAnchor.constraint(equalTo:stack.widthAnchor)])}
        return card
    }
    private func showHome(){
        setMenu(open:false,animated:false)
        portraitPlay=false;waitingForPortrait=false;portraitSelection=nil
        session.stop();machine.cancelTouches();openingLink?.invalidate();current=nil;choosing=true;selectingTheme=false;selectionIndex=DeviceModel.available(onPhone:isPhone).firstIndex(of:model) ?? 0;selectionCards=[];selectionPreviews.forEach{$0.setPreviewActive(false)};selectionPreviews=[];themeShelf.isHidden=true;themeHeading.isHidden=true;machine.isHidden=true;home.isHidden=false;pickerScroll.isHidden=false;shelf.isHidden=true;emptyLabel.isHidden=true;clear(home);updatePhoneOrientation()
        do {
            pickerScroll.isHidden=true;themeShelf.isHidden=false;themeHeading.isHidden=true;themeShelfTop.constant=12;themeHeading.isHidden=false;themeHeading.text="";homeBrand.isHidden=false;clear(themeCards);themeSizeConstraints=[]
            for kind in DeviceModel.available(onPhone:isPhone){
                let card=ShowcaseSelectionCard(type:.custom);card.accessibilityLabel=kind.name;card.backgroundColor = .clear;card.layer.cornerRadius=24
                let art=SpatialPreview(model:kind,theme:max(0,min(kind.themes.count-1,UserDefaults.standard.integer(forKey:"theme."+kind.rawValue))),showOpen:false,physicalComparison:true);card.preview=art;selectionPreviews.append(art);art.attachInteraction(to:card);art.inspectionChanged={[weak self] inspecting in self?.showcaseLight.show(self?.choosing ?? false)};
                let label=UILabel();label.text=kind.name;label.textAlignment = .center;label.numberOfLines=2;label.textColor=UIColor(hex:0xE2E8DC);label.font = .systemFont(ofSize:18,weight:.semibold)
                let stack=UIStackView(arrangedSubviews:[art]);stack.axis = .vertical;stack.spacing=12;stack.isUserInteractionEnabled=false;stack.translatesAutoresizingMaskIntoConstraints=false;card.addSubview(stack)
                let width=card.widthAnchor.constraint(equalToConstant:themeWidth),height=stack.heightAnchor.constraint(equalToConstant:themeHeight)
                NSLayoutConstraint.activate([width,height,stack.centerYAnchor.constraint(equalTo:card.centerYAnchor),stack.leadingAnchor.constraint(equalTo:card.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:card.trailingAnchor,constant:-16)])
                themeSizeConstraints += [width,height];card.addAction(UIAction{[weak self] _ in guard let self,let index=DeviceModel.available(onPhone:self.isPhone).firstIndex(of:kind) else{return};if self.selectionIndex != index{self.selectionIndex=index;self.updateSelection()}else{self.showThemes(kind)}},for:.touchUpInside);themeCards.addArrangedSubview(card);selectionCards.append(card)
            };themeViewport=0;toolbar();view.layoutIfNeeded();updateThemeMetrics();updateSelection();return
        }
    }
    private func showThemes(_ kind:DeviceModel){
        themeShelf.alpha=0;defer{UIView.animate(withDuration:0.28){self.themeShelf.alpha=1}}
        homeBrand.isHidden=true
        setMenu(open:false,animated:false)
        session.stop();machine.cancelTouches();model=kind;choosing=true;selectingTheme=true;selectionIndex=max(0,min(kind.themes.count-1,UserDefaults.standard.integer(forKey:"theme."+kind.rawValue)));selectionCards=[];selectionPreviews.forEach{$0.setPreviewActive(false)};selectionPreviews=[]
        machine.isHidden=true;home.isHidden=false;pickerScroll.isHidden=false;shelf.isHidden=true;emptyLabel.isHidden=true;clear(home);updatePhoneOrientation()
        themeShelf.isHidden=false;themeHeading.isHidden=false;themeHeading.text=kind.name;themeShelfTop.constant=12;pickerScroll.isHidden=true;clear(themeCards);themeSizeConstraints=[]
        for (index,name) in kind.themes.enumerated(){
            let card=ShowcaseSelectionCard(type:.custom);card.accessibilityLabel=name;card.backgroundColor = .clear;card.layer.cornerRadius=24
            let art=SpatialPreview(model:kind,theme:index,physicalComparison:true);card.preview=art;selectionPreviews.append(art);art.attachInteraction(to:card);art.inspectionChanged={[weak self] inspecting in self?.showcaseLight.show(self?.choosing ?? false)}
            let content=UIStackView(arrangedSubviews:[art]);content.axis = .vertical;content.spacing=0;content.isUserInteractionEnabled=false;content.translatesAutoresizingMaskIntoConstraints=false;card.addSubview(content)
            let width=card.widthAnchor.constraint(equalToConstant:themeWidth),height=content.heightAnchor.constraint(equalToConstant:themeHeight)
            NSLayoutConstraint.activate([width,height,content.centerYAnchor.constraint(equalTo:card.centerYAnchor),content.leadingAnchor.constraint(equalTo:card.leadingAnchor,constant:16),content.trailingAnchor.constraint(equalTo:card.trailingAnchor,constant:-16)])
            // Store image-stack height separately so the scroll shelf remains vertically centred.
            height.constant=themeHeight;themeSizeConstraints += [width,height]
            card.addAction(UIAction{[weak self] _ in guard let self else{return};self.theme=index;UserDefaults.standard.set(index,forKey:"theme."+kind.rawValue);self.choosing=false;self.selectingTheme=false;self.showLibrary()},for:.touchUpInside)
            selectionCards.append(card);themeCards.addArrangedSubview(card)
        };themeViewport=0;toolbar();view.layoutIfNeeded();updateThemeMetrics();updateSelection()
    }
    override var canBecomeFirstResponder:Bool{true}
    override var keyCommands:[UIKeyCommand]?{[UIKeyCommand(input:UIKeyCommand.inputLeftArrow,modifierFlags:[],action:#selector(moveSelection(_:))),UIKeyCommand(input:UIKeyCommand.inputRightArrow,modifierFlags:[],action:#selector(moveSelection(_:))),UIKeyCommand(input:UIKeyCommand.inputUpArrow,modifierFlags:[],action:#selector(moveSelection(_:))),UIKeyCommand(input:UIKeyCommand.inputDownArrow,modifierFlags:[],action:#selector(moveSelection(_:))),UIKeyCommand(input:"\r",modifierFlags:[],action:#selector(confirmSelection))]}
    private func updateFocus(){pages.numberOfPages=selectionCards.count;pages.currentPage=selectionIndex;pages.isHidden = !choosing;showcaseLight.show(choosing);
        if choosing && selectingTheme {
            let index=max(0,min(model.themes.count-1,selectionIndex)),title=NSMutableAttributedString(string:model.name+"\n",attributes:[.font:UIFont.systemFont(ofSize:17.5,weight:.semibold),.foregroundColor:UIColor(hex:0xEAE6D7)])
            title.append(NSAttributedString(string:model.themes[index],attributes:[.font:UIFont.systemFont(ofSize:13.5,weight:.medium),.foregroundColor:UIColor(hex:0xCEBC8D)]));themeHeading.attributedText=title
        }
        if choosing && !selectingTheme{let available=DeviceModel.available(onPhone:isPhone),index=max(0,min(selectionIndex,DeviceModel.available(onPhone:isPhone).count-1)),kind=available[index];homeBrandName.text=kind == .psp ? "SONY":"NINTENDO";if let path=Bundle.main.url(forResource:kind.rawValue+"-home",withExtension:"png",subdirectory:"Assets/Logos"){UIView.transition(with:homeBrandLogo,duration:0.20,options:.transitionCrossDissolve){self.homeBrandLogo.image=UIImage(contentsOfFile:path.path)}}}
        for (i,card) in selectionCards.enumerated(){card.layer.borderWidth=0;card.backgroundColor = .clear;if selectionPreviews.indices.contains(i){selectionPreviews[i].setFocused(i==selectionIndex);selectionPreviews[i].setFocusDistance(CGFloat(i)-CGFloat(selectionIndex));selectionPreviews[i].setPreviewActive(abs(i-selectionIndex)<=1)}}}
    private func updateSelection(){updateFocus();if choosing{themeShelf.setContentOffset(CGPoint(x:CGFloat(selectionIndex)*(themeStride)-themeShelf.contentInset.left,y:0),animated:true)};becomeFirstResponder()}
    func scrollViewDidScroll(_ scrollView:UIScrollView){if scrollView===shelf{updateCardVisibility();return};guard choosing,scrollView===themeShelf,!selectionCards.isEmpty,scrollView.isDragging || scrollView.isDecelerating else{return};let position=(scrollView.contentOffset.x+scrollView.contentInset.left)/(themeStride);for (i,preview) in selectionPreviews.enumerated(){preview.setFocusDistance(CGFloat(i)-position)};let index=max(0,min(selectionCards.count-1,Int(round(position))));if index != selectionIndex{selectionIndex=index;updateFocus()}}

    @objc private func moveSelection(_ key:UIKeyCommand){guard choosing,!selectionCards.isEmpty else{return};let columns=1;let delta=key.input==UIKeyCommand.inputLeftArrow ? -1:key.input==UIKeyCommand.inputRightArrow ? 1:key.input==UIKeyCommand.inputUpArrow ? -columns:columns;selectionIndex=(selectionIndex+delta+selectionCards.count)%selectionCards.count;updateSelection()}
    @objc private func confirmSelection(){guard choosing,selectionCards.indices.contains(selectionIndex) else{return};selectionCards[selectionIndex].sendActions(for:.touchUpInside)}
    private func showLibrary(){
        selectionPreviews.forEach{$0.setPreviewActive(false)}
        homeBrand.isHidden=true
        guard !session.running else{return};choosing=false;showcaseLight.show(false);selectingTheme=false;themeShelf.isHidden=true;themeHeading.isHidden=isPhone;themeHeading.text="选择游戏";syncMachinePosition();machine.isHidden=true;machine.alpha=1;machine.model=model;machine.theme=theme;machine.libraryMode=true;machine.playing=false;machine.bookMode=false;machine.openness=0;machine.frameImage=nil;home.isHidden=true;pickerScroll.isHidden=true;shelf.isHidden=false;shelf.alpha=1
        let oldIndex=max(0,Int(round((shelf.contentOffset.x+shelf.contentInset.left)/cardStride)));let sameModel=(cards.arrangedSubviews.first as? CartridgeView)?.item.model==model
        explicitCardPage=nil;clear(cards);let games=items.filter{$0.model==model};emptyLabel.isHidden = !games.isEmpty
        for item in games {let card=CartridgeView(item:item,library:library);card.widthAnchor.constraint(equalToConstant:cardWidth).isActive=true;card.addAction(UIAction{[weak self,weak card] _ in guard let self,let card else{return};self.insert(item,from:card)},for:.touchUpInside);cards.addArrangedSubview(card);covers.load(item){[weak self] in self?.reload()}}
        view.layoutIfNeeded();updateShelfInsets();let compact=shelf.contentSize.width<=shelf.bounds.width
        shelf.setContentOffset(CGPoint(x:(compact ? 0:CGFloat(sameModel ? min(oldIndex,max(0,games.count-1)):0)*cardStride)-shelf.contentInset.left,y:0),animated:false)
        toolbar();updatePhoneOrientation()
    }
    private func updateCardVisibility(){
        if !choosing{pages.numberOfPages=cards.arrangedSubviews.count;let nearest=cards.arrangedSubviews.enumerated().min{abs($0.element.convert($0.element.bounds,to:shelf).midX-shelf.bounds.midX)<abs($1.element.convert($1.element.bounds,to:shelf).midX-shelf.bounds.midX)};pages.currentPage=explicitCardPage ?? nearest?.offset ?? 0}
        for case let card as CartridgeView in cards.arrangedSubviews{card.setPreviewActive(!shelf.isHidden && card.convert(card.bounds,to:shelf).intersects(shelf.bounds));let distance=abs(card.convert(card.bounds,to:shelf).midX-shelf.bounds.midX)/max(1,card.bounds.width);card.setShelfFocus(explicitCardPage.map{cards.arrangedSubviews.firstIndex(of:card)==$0 ? 1:0} ?? max(0,1-distance))}}
    private func updateShelfInsets(){
        defer{updateCardVisibility()}
        let targetHeight=max(180,view.bounds.height-view.safeAreaInsets.top-view.safeAreaInsets.bottom-(isPhone ? 56:170))
        if abs(shelfHeight.constant-targetHeight)>0.5{shelfHeight.constant=targetHeight}
        for card in cards.arrangedSubviews{for constraint in card.constraints where constraint.firstAttribute == .width && constraint.secondItem == nil{if abs(constraint.constant-cardWidth)>0.5{constraint.constant=cardWidth}}}
        let groupWidth=CGFloat(cards.arrangedSubviews.count)*cardWidth+CGFloat(max(0,cards.arrangedSubviews.count-1))*22+48
        let inset=max(0,(shelf.bounds.width-(groupWidth<=shelf.bounds.width ? groupWidth:cardWidth+48))/2)
        guard abs(shelf.contentInset.left-inset)>0.5 else{return}
        let old=shelf.contentInset.left,offset=shelf.contentOffset.x
        shelf.contentInset=UIEdgeInsets(top:0,left:inset,bottom:0,right:inset)
        shelf.contentOffset=CGPoint(x:offset+old-inset,y:0)
    }
    private var pickerDragStart=0
    func scrollViewWillBeginDragging(_ scrollView:UIScrollView){if scrollView===shelf{explicitCardPage=nil};if scrollView===themeShelf{pickerDragStart=selectionIndex;selectionPreviews.forEach{$0.setBrowsing(true)}}}
    func scrollViewDidEndDragging(_ scrollView:UIScrollView,willDecelerate decelerate:Bool){if scrollView===themeShelf,!decelerate{selectionPreviews.forEach{$0.setBrowsing(false)}}}
    func scrollViewDidEndDecelerating(_ scrollView:UIScrollView){if scrollView===themeShelf{selectionPreviews.forEach{$0.setBrowsing(false)}}}
    func scrollViewDidEndScrollingAnimation(_ scrollView:UIScrollView){if scrollView===themeShelf{selectionPreviews.forEach{$0.setBrowsing(false)}}}
    func scrollViewWillEndDragging(_ scrollView:UIScrollView,withVelocity velocity:CGPoint,targetContentOffset:UnsafeMutablePointer<CGPoint>){
        if scrollView===themeShelf {
            let position=(scrollView.contentOffset.x+themeShelf.contentInset.left)/(themeStride)
            let index=CGFloat(PickerMotion.snappedIndex(position:position,velocity:velocity.x,start:pickerDragStart,count:selectionCards.count))
            selectionIndex=Int(index);targetContentOffset.pointee.x=index*(themeStride)-themeShelf.contentInset.left
            updateFocus();return
        }
        guard scrollView===shelf,shelf.contentSize.width>shelf.bounds.width else{return}
        let index=max(0,min(CGFloat(cards.arrangedSubviews.count-1),round((targetContentOffset.pointee.x+shelf.contentInset.left)/cardStride)))
        targetContentOffset.pointee.x=index*cardStride-shelf.contentInset.left
    }
    private func insert(_ item:ROMItem,from card:CartridgeView){
        guard !loading else{return}
        if isPhone && model == .gbc && !portraitPlay {
            portraitPlay=true;waitingForPortrait=true;portraitSelection=(item,card);loading=true;toolbar();machine.cancelTouches();updatePhoneOrientation()
            DispatchQueue.main.asyncAfter(deadline:.now()+0.7){[weak self] in self?.finishPortraitSelection()};return
        }
        loading=true;themeHeading.isHidden=true;machine.isHidden=false;machine.alpha=0;UIView.animate(withDuration:0.28){self.machine.alpha=1};machine.cancelTouches();pendingItem=item;toolbar();mediaSeatFeedbackSent=false;PhoneHaptics.pickUp();MediaSound.shared.beginLoading(model.rawValue)
        let ghost=UIImageView(image:card.mediaImage);ghost.contentMode = .scaleAspectFit;ghost.isUserInteractionEnabled=false;ghost.frame=card.convert(card.pickupRect,to:view);card.alpha=0;view.addSubview(ghost);insertionGhost=ghost;insertionFrom=ghost.frame;ghost.layer.shadowColor=UIColor.black.cgColor;ghost.layer.shadowOpacity=0.4;ghost.layer.shadowRadius=14;ghost.layer.shadowOffset=CGSize(width:0,height:10);UIView.animate(withDuration:0.22){self.shelf.alpha=0}
        machine.loadedMediaImage=card.mediaImage
        if machine.spatial.available {ghost.alpha=0;machine.spatial.startMedia(model:model,cover:library.coverURL(item).flatMap{UIImage(contentsOfFile:$0.path)},tint:item.dominantRGB ?? 0x6C8175,title:item.title)}
        let l=machine.layout,slot=CartridgeSlot.load(model),y:CGFloat=slot?.y ?? 175
        insertionSlot=machine.spatial.slotPoint() ?? l.rect(CGRect(x:l.geometry.size.width/2,y:y,width:0,height:0)).origin
        let width:CGFloat=(model == .psp ? 260*SpatialMachine.mediaScale("psp"):slot?.cardWidth ?? 178)*l.scale
        let ratio=slot?.ratio ?? (card.mediaRect.height/card.mediaRect.width)
        insertionTo=CGRect(x:insertionSlot.x-width/2,y:insertionSlot.y-(model == .psp ? width*ratio/2:width*ratio+12),width:width,height:width*ratio)
        insertionStart=CACurrentMediaTime();let link=CADisplayLink(target:self,selector:#selector(animateInsertion));link.add(to:.main,forMode:.common);insertionLink=link
    }
    private func finishPortraitSelection(){
        guard waitingForPortrait,view.bounds.height>view.bounds.width,let (item,card)=portraitSelection else{return}
        waitingForPortrait=false;portraitSelection=nil;loading=false;view.layoutIfNeeded();insert(item,from:card)
    }
    @objc private func animateInsertion(){
        guard let ghost=insertionGhost else{return};let t=CGFloat(min(1,(CACurrentMediaTime()-insertionStart)/Double(SpatialMachine.insertionTime(model.rawValue))))
        func ease(_ value:CGFloat)->CGFloat{let x=max(0,min(1,value));return x*x*x*(x*(x*6-15)+10)}
        let travel=ease((t-0.18)/0.4);var frame=CGRect(x:insertionFrom.minX+(insertionTo.minX-insertionFrom.minX)*travel,y:insertionFrom.minY+(insertionTo.minY-insertionFrom.minY)*travel,width:insertionFrom.width+(insertionTo.width-insertionFrom.width)*travel,height:insertionFrom.height+(insertionTo.height-insertionFrom.height)*travel)
        let push=ease((t-0.58)/0.26);frame.origin.y += (model == .psp ? 0:frame.height+12)*push;frame.origin.y -= 18*sin(min(1,t/0.58) * .pi);ghost.layer.transform=CATransform3DIdentity;ghost.frame=frame;ghost.layer.transform=CATransform3DMakeRotation(-0.10*sin(min(1,t/0.58) * .pi),0,0,1)
        MediaSound.shared.advanceLoading(model.rawValue,progress:t)
        machine.loadingProgress=t
        if machine.spatial.available{machine.spatial.updateMedia(rect:frame,progress:t)}
        if !mediaSeatFeedbackSent,t >= (model == .psp ? 0.84:0.85){mediaSeatFeedbackSent=true;PhoneHaptics.seat(disc:model == .psp)}
        #if DEBUG
        captureAnimation("insert",t)
        #endif
        if model == .psp {ghost.isHidden=t>0.72}else if t>0.5 {let mask=CAShapeLayer();mask.path=UIBezierPath(rect:CGRect(x:0,y:0,width:frame.width,height:max(0,insertionSlot.y-frame.minY))).cgPath;ghost.layer.mask=mask}
        if t>=1 {
            insertionLink?.invalidate();insertionLink=nil;ghost.removeFromSuperview();insertionGhost=nil;machine.spatial.keepMedia();machine.loadingProgress=0
            guard let item=pendingItem else{loading=false;return};pendingItem=nil
            current=item;machine.libraryMode=false;machine.playing=true;shelf.isHidden=true;emptyLabel.isHidden=true;openingStart=CACurrentMediaTime();let link=CADisplayLink(target:self,selector:#selector(animateOpen));link.add(to:.main,forMode:.common);openingLink=link;toolbar()
        }
    }
    @objc private func animateOpen(){let t=min(1,(CACurrentMediaTime()-openingStart)/1.35);machine.openness=CGFloat(t*t*t*(t*(t*6-15)+10))
        #if DEBUG
        captureAnimation("open",CGFloat(t))
        #endif
        if t>=1{openingLink?.invalidate();openingLink=nil
            if let item=current {do{try session.start(item,library:library)}catch{machine.playing=false;showError(error.localizedDescription)}}
            loading=false;toolbar()
        }}
    private func syncMachinePosition(){
        let landscape=view.bounds.width>view.bounds.height,key="machine.y."+model.rawValue+(landscape ? ".landscape":".portrait")
        if positionKey != key {positionKey=key
            machine.verticalPosition=UserDefaults.standard.object(forKey:key)==nil ? (UIDevice.current.userInterfaceIdiom == .phone ? 0.5:landscape ? 0.86:0.58):CGFloat(UserDefaults.standard.double(forKey:key))
            machine.horizontalPosition=UserDefaults.standard.object(forKey:key+".x")==nil ? 0.5:CGFloat(UserDefaults.standard.double(forKey:key+".x"))
            machine.displayZoom=UserDefaults.standard.object(forKey:key+".zoom")==nil ? 1:CGFloat(UserDefaults.standard.double(forKey:key+".zoom"))
            machine.screenFirst=UserDefaults.standard.bool(forKey:"display.focus."+model.rawValue)
        }
    }
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();syncMachinePosition();updateShelfInsets();updateThemeMetrics()}
    @objc private func positionPanel(_ sender:UIButton){
        guard !loading else{return};machine.cancelTouches()
        let controller=UIViewController();controller.preferredContentSize=CGSize(width:320,height:420);controller.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .phone ? .pageSheet:.popover;controller.view.backgroundColor=UIColor(hex:0x27322C)
        if let sheet=controller.sheetPresentationController {sheet.detents=[.custom{_ in 420}];sheet.prefersGrabberVisible=true;sheet.prefersEdgeAttachedInCompactHeight=true}
        let stack=UIStackView();stack.axis = .vertical;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false;let scroll=UIScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false;controller.view.addSubview(scroll);scroll.addSubview(stack);NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:controller.view.safeAreaLayoutGuide.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:controller.view.safeAreaLayoutGuide.trailingAnchor),scroll.topAnchor.constraint(equalTo:controller.view.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:controller.view.safeAreaLayoutGuide.bottomAnchor),stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:22),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-20),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-40)])
        func label(_ text:String){let l=UILabel();l.text=text;l.textColor=UIColor(hex:0xE4E6DE);l.font = .systemFont(ofSize:15,weight:.medium);stack.addArrangedSubview(l)}
        label("显示调整");if isPhone{let close=UIButton(type:.system);close.setTitle("完成",for:.normal);close.heightAnchor.constraint(equalToConstant:44).isActive=true;close.addAction(UIAction{[weak controller] _ in controller?.dismiss(animated:true)},for:.touchUpInside);stack.addArrangedSubview(close)}
        if UIDevice.current.userInterfaceIdiom == .pad {
            let mode=UISegmentedControl(items:["仿真机身","大屏操控"]);mode.selectedSegmentIndex=machine.screenFirst ? 1:0;mode.addAction(UIAction{[weak self,weak mode] _ in guard let self else{return};self.machine.screenFirst=mode?.selectedSegmentIndex==1;UserDefaults.standard.set(self.machine.screenFirst,forKey:"display.focus."+self.model.rawValue);self.machine.displayZoom=1;UserDefaults.standard.set(1,forKey:self.positionKey+".zoom")},for:.valueChanged);stack.addArrangedSubview(mode)
        }
        var sliders:[UISlider]=[]
        for (index,title) in ["画面大小","左右位置","上下位置"].enumerated(){label(title);let slider=UISlider();slider.minimumValue=index==0 ? 0.55:0;slider.maximumValue=index==0 && UIDevice.current.userInterfaceIdiom == .pad && !machine.screenFirst ? 1.6:1;slider.value=Float(index==0 ? machine.displayZoom:index==1 ? machine.horizontalPosition:machine.verticalPosition);slider.tag=index;slider.accessibilityLabel=title;slider.minimumTrackTintColor=UIColor(hex:0x9DB398);slider.addTarget(self,action:#selector(displayChanged(_:)),for:.valueChanged);stack.addArrangedSubview(slider);sliders.append(slider)}
        if UIDevice.current.userInterfaceIdiom == .phone {let row=UIStackView();row.axis = .horizontal;let label=UILabel();label.text="按键与插拔触感";label.textColor=UIColor(hex:0xDEE6D9);label.font = .systemFont(ofSize:14);row.addArrangedSubview(label);let toggle=UISwitch();toggle.isOn=machine.hapticsEnabled;toggle.addAction(UIAction{[weak toggle] _ in UserDefaults.standard.set(toggle?.isOn ?? true,forKey:"controls.haptics")},for:.valueChanged);row.addArrangedSubview(toggle);stack.addArrangedSubview(row)}
        let reset=UIButton(type:.system);reset.setTitle("恢复默认布局",for:.normal);reset.tintColor=UIColor(hex:0xDEE6D9);reset.heightAnchor.constraint(equalToConstant:44).isActive=true
        reset.addAction(UIAction{[weak self] _ in guard let self else{return};for suffix in ["",".x",".zoom"]{UserDefaults.standard.removeObject(forKey:self.positionKey+suffix)};self.positionKey="";self.syncMachinePosition();sliders[0].value=Float(self.machine.displayZoom);sliders[1].value=Float(self.machine.horizontalPosition);sliders[2].value=Float(self.machine.verticalPosition)},for:.touchUpInside);stack.addArrangedSubview(reset)
        controller.popoverPresentationController?.sourceView=sender;controller.popoverPresentationController?.sourceRect=sender.bounds;present(controller,animated:true)
    }
    @objc private func displayChanged(_ slider:UISlider){machine.cancelTouches();let value=CGFloat(slider.value);if slider.tag==0 {machine.displayZoom=value;UserDefaults.standard.set(Double(value),forKey:positionKey+".zoom")}else if slider.tag==1{machine.horizontalPosition=value;UserDefaults.standard.set(Double(value),forKey:positionKey+".x")}else{machine.verticalPosition=value;UserDefaults.standard.set(Double(value),forKey:positionKey)}}
    @objc private func toggleBook(){guard !loading else{return};machine.cancelTouches();UIView.animate(withDuration:0.45,delay:0,options:[.curveEaseInOut]){self.machine.bookMode.toggle();self.machine.layoutIfNeeded()};toolbar()}
    private func showSpatialSwitcher(_ shown:((SpatialSwitchController)->Void)?=nil){
        guard !loading else{return};guard session.running else{showHome();return};machine.cancelTouches();session.pause()
        let models=DeviceModel.available(onPhone:isPhone),entries=models.map{kind in SpatialCarouselEntry(model:kind.rawValue,title:kind.name,theme:max(0,min(kind.themes.count-1,UserDefaults.standard.integer(forKey:"theme."+kind.rawValue))))}
        let controller=SpatialSwitchController(entries:entries,selected:models.firstIndex(of:model) ?? 0)
        controller.onClose={[weak self] index in guard let self else{return};if let index,models[index] != self.model{self.portraitPlay=false;self.showThemes(models[index])}else if self.session.running{self.session.resume()}}
        present(controller,animated:true){shown?(controller)}
    }
    @objc private func titleTapped(){guard !loading else{return};if session.running{showSpatialSwitcher()}else if !choosing{showThemes(model)}else{showHome()}}
    @objc private func instantStateMenu(){
        let alert=UIAlertController(title:"随时存，随时接着玩",message:nil,preferredStyle:.alert)
        for (title,restore,slot) in [("存下此刻",false,0),("恢复手动存档",true,0),("继续上次离开",true,1)]{alert.addAction(UIAlertAction(title:title,style:.default){[weak self] _ in self?.instantState(restore,slot:slot)})}
        alert.addAction(UIAlertAction(title:"取消",style:.cancel));present(alert,animated:true)
    }
    private func instantState(_ restore:Bool,slot:Int){
        guard session.running else{return};machine.cancelTouches();session.pause()
        func execute(){let result=self.session.instantState(restore:restore,slot:slot);let message=result==1 ? (restore ? "已恢复进度":"此刻已保存"):String(cString:emu_state_error());if result == -2{self.changeCartridge()};let notice=UIAlertController(title:result==1 ? "即时存档":"即时存档未完成",message:message,preferredStyle:.alert);notice.addAction(UIAlertAction(title:"好",style:.default){[weak self] _ in self?.session.resume()});self.present(notice,animated:true)}
        if restore{let alert=UIAlertController(title:"恢复这份即时存档？",message:"当前画面会回到保存时的位置。游戏内存档仍单独保留。",preferredStyle:.alert);alert.addAction(UIAlertAction(title:"恢复",style:.default){_ in execute()});alert.addAction(UIAlertAction(title:"取消",style:.cancel){[weak self] _ in self?.session.resume()});present(alert,animated:true)}else{execute()}
    }
    @objc private func changeCartridge(){guard !loading else{return};if session.running{PhoneHaptics.eject()}else{PhoneHaptics.press()};session.stop();machine.cancelTouches();openingLink?.invalidate();openingLink=nil;current=nil;portraitPlay=false;showLibrary()}
    @objc private func power(){guard !loading else{return};if session.running{changeCartridge()}else{PhoneHaptics.press();showHome()}}
    @objc private func importROM(){
        guard !loading else{return};if session.running{session.pause()};machine.cancelTouches()
        let supportedExtensions=UIDevice.current.userInterfaceIdiom == .phone ? ["gba","gb","gbc","iso","cso","chd","pbp"]:["nds","gba","gb","gbc","cci","3ds","cxi","iso","cso","chd","pbp"]
        let types=[UTType.zip]+supportedExtensions.compactMap{UTType(filenameExtension:$0,conformingTo:.data)}
        let picker=UIDocumentPickerViewController(forOpeningContentTypes:types,asCopy:false);picker.allowsMultipleSelection=true;picker.delegate=self;present(picker,animated:true)
    }
    func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){if session.running{session.resume()}}
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){
        loading=true;busy.startAnimating();library.importFiles(urls){[weak self] summary in guard let self else{return};self.loading=false;self.busy.stopAnimating();if self.session.running{self.session.resume()};self.reload();let message="已添加 \(summary.added.count) 个，跳过重复 \(summary.duplicateCount) 个。"+(summary.failures.isEmpty ? "":"\n"+summary.failures.joined(separator:"\n"));self.showError(message,title:"导入完成")}
    }
    private func showError(_ message:String,title:String="暂时无法启动"){let alert=UIAlertController(title:title,message:message,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"好",style:.default));present(alert,animated:true)}
    private func cancelInsertion(){shelf.alpha=1;insertionLink?.invalidate();insertionLink=nil;insertionGhost?.removeFromSuperview();insertionGhost=nil;pendingItem=nil;loading=false;toolbar();machine.loadingProgress=0;for card in cards.arrangedSubviews{card.alpha=1}}
    func pause(){cancelInsertion();machine.cancelTouches();session.pause()}
    func resume(){if session.running{session.resume()}}
    override func viewWillTransition(to size:CGSize,with coordinator:UIViewControllerTransitionCoordinator){machine.cancelTouches();super.viewWillTransition(to:size,with:coordinator);coordinator.animate(alongsideTransition:{_ in self.view.layoutIfNeeded();self.machine.setNeedsDisplay()},completion:{_ in self.finishPortraitSelection()})}
}

final class CartridgeView:UIControl {
    let item:ROMItem,library:ROMLibrary
    private var spatialPreview:SpatialPreview?
    private var metadataObserver:NSObjectProtocol?
    private var shelfFocus:CGFloat=0
    override var isHighlighted:Bool{didSet{spatialPreview?.setCardLift(isHighlighted ? 1:shelfFocus)}}
    func setPreviewActive(_ active:Bool){spatialPreview?.setPreviewActive(active)}
    func setShelfFocus(_ value:CGFloat){shelfFocus=value;spatialPreview?.setCardLift(isHighlighted ? 1:value)}
    override func layoutSubviews(){super.layoutSubviews();let r=mediaRect;spatialPreview?.frame=r.insetBy(dx:-r.width*0.09,dy:-r.height*0.09)}
    private var titleHeight:CGFloat {let font=UIFont.systemFont(ofSize:UIDevice.current.userInterfaceIdiom == .phone ? 11:13,weight:.semibold);return ceil((GameCatalog.title(item.title) as NSString).boundingRect(with:CGSize(width:max(1,bounds.width),height:90),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font],context:nil).height)}
    private var factsHeight:CGFloat {UIDevice.current.userInterfaceIdiom == .phone ? 68:80}
    var metadataFits:Bool{mediaRect.maxY+8+titleHeight+6+factsHeight<=bounds.height+1}
    func drawSpatialSnapshot(in target:UIView){if let spatialPreview{spatialPreview.snapshot().draw(in:spatialPreview.convert(spatialPreview.bounds,to:target))}}
    var pickupRect:CGRect{mediaRect.offsetBy(dx:0,dy:-(spatialPreview?.cardLiftOffset ?? 0))}
    var mediaRect:CGRect {let ratio:CGFloat=item.model == .psp ? 1:CartridgeSlot.load(item.model)?.ratio ?? 1;let width=min(max(1,bounds.width-12),max(1,bounds.height-titleHeight-factsHeight-14)/ratio);let size=CGSize(width:width,height:width*ratio);return CGRect(x:(bounds.width-width)/2,y:max(0,bounds.height-titleHeight-factsHeight-14-size.height),width:size.width,height:size.height)}
    var mediaImage:UIImage {UIGraphicsImageRenderer(size:mediaRect.size).image{_ in drawMedia(CGRect(origin:.zero,size:mediaRect.size))}}
    init(item:ROMItem,library:ROMLibrary){self.item=item;self.library=library;super.init(frame:.zero);backgroundColor = .clear;isAccessibilityElement=true;accessibilityLabel="插入 "+item.title;accessibilityTraits = .button;let preview=SpatialPreview(model:item.model,cover:library.coverURL(item).flatMap{UIImage(contentsOfFile:$0.path)},tint:item.dominantRGB ?? 0x6C8175,title:item.title);addSubview(preview);spatialPreview=preview;preview.attachInteraction(to:self);library.catalog.request(model:item.model.rawValue,name:item.catalogName ?? item.title);metadataObserver=NotificationCenter.default.addObserver(forName:GameCatalog.changed,object:library.catalog,queue:.main){[weak self] _ in self?.setNeedsDisplay()}}
    deinit{if let metadataObserver{NotificationCenter.default.removeObserver(metadataObserver)}}
    required init?(coder:NSCoder){fatalError()}
    private func word(_ text:String,_ r:CGRect,_ size:CGFloat,_ ink:UIColor){let p=NSMutableParagraphStyle();p.alignment = .center;(text as NSString).draw(in:r,withAttributes:[.font:UIFont.systemFont(ofSize:size,weight:.semibold),.foregroundColor:ink,.paragraphStyle:p])}
    // Dimensions and moulding details mirror drawClassicCard / drawModernMedia on Mac.
    private func drawMedia(_ target:CGRect){
        guard let c=UIGraphicsGetCurrentContext() else{return};c.saveGState();defer{c.restoreGState()}
        let gba=item.model == .gba,gbc=item.model == .gbc,psp=item.model == .psp,modern=psp || item.model == .n3ds
        let w:CGFloat=gba ? 180:gbc ? 132:modern ? 160:174,h:CGFloat=gba ? 104:gbc ? 150:modern ? 160:188
        c.translateBy(x:target.minX,y:target.minY);c.scaleBy(x:target.width/w,y:target.height/h)
        let color=UIColor(hex:item.dominantRGB ?? 0x6C8175),ink=UIColor(hex:0xDDE5D8),r=CGRect(x:2,y:2,width:w-4,height:h-7)
        let body=UIBezierPath(roundedRect:r,cornerRadius:psp ? 36:7)
        if item.model == .n3ds {body.removeAllPoints();body.move(to:CGPoint(x:6,y:3));for p in [CGPoint(x:158,y:3),CGPoint(x:158,y:30),CGPoint(x:150,y:30),CGPoint(x:150,y:150),CGPoint(x:141,y:157),CGPoint(x:9,y:157),CGPoint(x:2,y:148),CGPoint(x:2,y:9)]{body.addLine(to:p)};body.close()}
        UIColor(hex:modern ? 0xE2E2D8:0x34413C).setFill();body.fill();color.withAlphaComponent(modern ? 0.30:0.68).setFill();body.fill()
        c.saveGState();body.addClip();let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[UIColor.white.withAlphaComponent(0.22).cgColor,UIColor.clear.cgColor,UIColor.black.withAlphaComponent(0.32).cgColor] as CFArray,locations:[0,0.4,1])!;c.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:w,y:h),options:[])
        if !modern {for i in 0..<4 {let x=w*(0.13+CGFloat(i)*0.21);UIColor(hex:0x263F31,alpha:0.2).setFill();UIBezierPath(rect:CGRect(x:x,y:12,width:9,height:h-22)).fill()}}
        c.restoreGState();UIColor.white.withAlphaComponent(0.3).setStroke();body.lineWidth=0.9;body.stroke()
        let label:CGRect=gba ? CGRect(x:21,y:26,width:138,height:62):gbc ? CGRect(x:17,y:43,width:98,height:88):psp ? CGRect(x:11,y:6,width:138,height:138):item.model == .n3ds ? CGRect(x:19,y:34,width:114,height:100):CGRect(x:17,y:37,width:140,height:118)
        if !psp {UIColor(hex:0x222D28).setFill();UIBezierPath(roundedRect:label.insetBy(dx:-2,dy:-2),cornerRadius:4).fill()}
        c.saveGState();(psp ? UIBezierPath(ovalIn:label):UIBezierPath(roundedRect:label,cornerRadius:2)).addClip()
        if let file=library.coverURL(item),let image=UIImage(contentsOfFile:file.path){image.draw(in:label)};c.restoreGState()
        if psp {UIColor(hex:0xE5E6DF).setFill();UIBezierPath(ovalIn:CGRect(x:51,y:46,width:58,height:58)).fill();word("UMD",CGRect(x:51,y:60,width:58,height:25),17,UIColor(hex:0x597AB3));word("UNIVERSAL MEDIA DISC",CGRect(x:52,y:84,width:56,height:7),3.5,.gray);word("PSP",CGRect(x:13,y:144,width:42,height:10),8,.gray)}
        else if gba {word("GAME BOY ADVANCE",CGRect(x:25,y:8,width:130,height:12),7,ink);for x in [CGFloat(4),w-25]{UIColor.black.withAlphaComponent(0.3).setFill();UIBezierPath(roundedRect:CGRect(x:x,y:1,width:21,height:12),cornerRadius:2).fill()};word("AGB-002",CGRect(x:20,y:h-13,width:w-40,height:9),5,ink)}
        else if gbc {word("GAME BOY",CGRect(x:18,y:16,width:w-36,height:18),10,ink);for y in [CGFloat(38),44,50]{for x in [CGFloat(3),w-14]{UIColor.black.withAlphaComponent(0.3).setFill();UIBezierPath(rect:CGRect(x:x,y:y,width:11,height:1)).fill()}};word("CGB-002",CGRect(x:20,y:h-13,width:w-40,height:9),5,ink)}
        else {word(item.model == .n3ds ? "NINTENDO 3DS":"NINTENDO DS",CGRect(x:14,y:14,width:w-28,height:16),10,modern ? .darkGray:ink);word(item.model == .n3ds ? "LNA-CTR":"NTR-005",CGRect(x:20,y:h-17,width:w-40,height:10),6,modern ? .darkGray:ink)}
    }
    override func draw(_ rect:CGRect){
        if spatialPreview == nil{drawMedia(mediaRect)}
        let style=NSMutableParagraphStyle();style.alignment = .center;style.lineBreakMode = .byWordWrapping
        let onPhone=UIDevice.current.userInterfaceIdiom == .phone,title=GameCatalog.title(item.title),font=UIFont.systemFont(ofSize:onPhone ? 11:13,weight:.semibold)
        let titleArea=CGRect(x:0,y:mediaRect.maxY+8,width:bounds.width,height:titleHeight)
        (title as NSString).draw(in:titleArea,withAttributes:[.font:font,.foregroundColor:UIColor(hex:0xE4E4D8),.paragraphStyle:style])
        let record=library.catalog.cached(model:item.model.rawValue,name:item.catalogName ?? item.title)
        let facts=["开发 · "+(record?.developer ?? "/"),"出品 · "+(record?.publisher ?? "/"),"发售 · "+(record?.releaseDate ?? "/")+(record?.releaseRegion.map{" · "+$0} ?? ""),"Metacritic · "+(record?.scoreText ?? "/")]
        for (i,line) in facts.enumerated(){(line as NSString).draw(in:CGRect(x:0,y:titleArea.maxY+6+CGFloat(i)*factsHeight/4,width:bounds.width,height:factsHeight/4),withAttributes:[.font:UIFont.systemFont(ofSize:onPhone ? 9:11,weight:i==3 ? .semibold:.regular),.foregroundColor:UIColor(hex:i==3 ? 0xD5C491:0xADB6A9),.paragraphStyle:style])}
        accessibilityValue=facts.joined(separator:"，")
    }
}

// A horizontal pan must cancel a card's tap rather than leave it captured by UIControl.
private final class GameShelfScrollView:UIScrollView {
    override func touchesShouldCancel(in view:UIView)->Bool{true}
}

// Overlapping transparent preview canvases must not steal taps from a neighbour.
private final class ShowcaseSelectionCard:UIButton {
 weak var preview:SpatialPreview?
 weak var caption:UILabel?
 override func layoutSubviews(){super.layoutSubviews();guard let preview,let caption else{return};preview.layoutIfNeeded();let solid=preview.convert(preview.projectedSolidBounds,to:self),height=min(44,max(24,caption.sizeThatFits(CGSize(width:bounds.width,height:44)).height));caption.frame=CGRect(x:0,y:max(0,min(bounds.height-height-4,solid.maxY+8)),width:bounds.width,height:height)}
 override func point(inside point:CGPoint,with event:UIEvent?)->Bool {
  guard let preview else{return super.point(inside:point,with:event)}
  return preview.convert(preview.projectedSolidBounds,to:self).insetBy(dx:-12,dy:-12).contains(point) || caption?.frame.contains(point)==true
 }
}
