import UIKit
@main final class AppDelegate:UIResponder,UIApplicationDelegate {
    func application(_ application:UIApplication,configurationForConnecting connectingSceneSession:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration {let config=UISceneConfiguration(name:"Uncle Ed",sessionRole:connectingSceneSession.role);config.delegateClass=SceneDelegate.self;return config}
}
final class SceneDelegate:UIResponder,UIWindowSceneDelegate {
    var window:UIWindow?
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options connectionOptions:UIScene.ConnectionOptions){guard let scene=scene as? UIWindowScene else{return};let window=UIWindow(windowScene:scene);window.rootViewController=GameViewController();window.backgroundColor=UIColor(hex:0x191E1D);window.makeKeyAndVisible();self.window=window}
    func sceneWillResignActive(_ scene:UIScene){(window?.rootViewController as? GameViewController)?.pause()}
    func sceneDidBecomeActive(_ scene:UIScene){(window?.rootViewController as? GameViewController)?.resume()}
    func sceneDidDisconnect(_ scene:UIScene){(window?.rootViewController as? GameViewController)?.session.stop()}
}
