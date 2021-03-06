//
//  BMUploadImageUtils.m
//  WeexDemo
//
//  Created by XHY on 2017/2/10.
//  Copyright © 2017年 taobao. All rights reserved.
//

#import "BMUploadImageUtils.h"
#import "BMDefine.h"
#import "UIImage+Util.h"
#import "NSDictionary+Util.h"
#import <SVProgressHUD.h>

#import <MobileCoreServices/MobileCoreServices.h>

#import "BMUploadImageRequest.h"

#import <TZImagePickerController/TZImagePickerController.h>
#import <TZImagePickerController/TZImageManager.h>

#import <SDWebImage/SDImageCache.h>


@interface BMUploadImageUtils () <UIActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIAlertViewDelegate>

@property(nonatomic, weak) WXSDKInstance *weexInstance;
@property(nonatomic, copy) WXModuleCallback callback;
@property(nonatomic, strong) BMUploadImageModel *imageInfo;
@property(nonatomic, assign) BOOL isLocal; /**< 通过此参数判断是否返回本地的图片地址 */

@end

@implementation BMUploadImageUtils

#pragma mark - Setter / Getter

#pragma mark - Custom Views

#pragma mark - Api Request


/* 先将图片上传至图片服务器然后在将返回的图片id上传至后台服务器 */
- (void)uploadImage:(NSArray<UIImage *> *)images {
    [SVProgressHUD showWithStatus:@"处理中.."];

    NSMutableArray *arr4Request = [NSMutableArray array];
    for (UIImage *image in images) {
        BMUploadImageRequest *api = [[BMUploadImageRequest alloc] initWithImage:image uploadImageModel:self.imageInfo];
        [arr4Request addObject:api];
    }

    YTKBatchRequest *batchRequest = [[YTKBatchRequest alloc] initWithRequestArray:arr4Request];

    [batchRequest startWithCompletionBlockWithSuccess:^(YTKBatchRequest *_Nonnull batchRequest) {

        [SVProgressHUD dismiss];

        NSMutableArray *arr4ImagesUrl = [NSMutableArray array];

        for (BMUploadImageRequest *request in batchRequest.requestArray) {
            id result = [request responseObject];
            [arr4ImagesUrl addObject:result ?: @""];
        }
        if (self.callback) {
            NSDictionary *backData = [NSDictionary configCallbackDataWithResCode:BMResCodeSuccess msg:nil data:arr4ImagesUrl];
            self.callback(backData);
        }

    }                                         failure:^(YTKBatchRequest *_Nonnull batchRequest) {
        [SVProgressHUD dismiss];

        if (self.callback) {
            // 获取错误code
            NSNumber *errorCode = [NSNumber numberWithInteger:batchRequest.failedRequest.responseStatusCode ?: -1];
            NSString *msg = [NSString getStatusText:[errorCode integerValue]];
            NSDictionary *resData = @{
                @"status": errorCode,
                @"errorMsg": msg,
                @"data": @{}
            };
            self.callback(resData);
        }

    }];
}

#pragma mark - Private Method

- (void)selectImage {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                       delegate:self
                                              cancelButtonTitle:@"取消"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"拍照", @"去相册选择", nil];

    [sheet showInView:[UIApplication sharedApplication].keyWindow];
}

//相册
- (void)LocalPhoto {

    TZImagePickerController *imagePickerVc = [[TZImagePickerController alloc] initWithMaxImagesCount:self.imageInfo.maxCount delegate:nil];

    /* 设置图片自动裁剪尺寸 */

//    if (self.imageInfo.imageWidth > 0) {
//        imagePickerVc.photoWidth = self.imageInfo.imageWidth;
//    }

    /* 设置不允许选择视频/gif/原图 */
    imagePickerVc.allowPickingVideo = NO;
    imagePickerVc.allowPickingGif = YES;
    imagePickerVc.allowPickingOriginalPhoto = NO;
    imagePickerVc.allowTakePicture = NO;
    imagePickerVc.allowCrop = NO;
    imagePickerVc.allowPickingMultipleVideo = YES;

    /* 判断是否是上传头像如果是则 允许裁剪图片 */
//    if (self.imageInfo.allowCrop && self.imageInfo.maxCount == 1) {
//        imagePickerVc.allowCrop = YES;
//        imagePickerVc.cropRect = CGRectMake(0, ([UIScreen mainScreen].bounds.size.height - [UIScreen mainScreen].bounds.size.width) / 2.0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.width);
//    }

    // 清理Lib/tmp/cropper.jpeg
    // 操作转移到getImagePath中


    __weak typeof(self) weakSelf = self;
    [imagePickerVc setDidFinishPickingPhotosHandle:^(NSArray<UIImage *> *photos, NSArray *assets, BOOL isSelectOriginalPhoto) {

        if (weakSelf.isLocal) {

            BOOL isGIF = [[assets[0] valueForKey:@"filename"] hasSuffix:@"GIF"];

            CGFloat fixelW = CGImageGetWidth(photos[0].CGImage);
            CGFloat fixelH = CGImageGetHeight(photos[0].CGImage);

            // 1. 默认情况下 cropper.html 中只会显示静态的图片
            // 2. 在处理gif的时候，如果要满足1，那么需要把文件copy到tmp/cropper.gif 下
            // 3. 使用gif，需要事先保存gif，返回路径，给到js端使用。
            // 4. 正式发送gif的时候，需要把图片转移到对应用户的名下
            // 5. 图片清理策略，截取多个图片一次发送的场景 （信）
            // todo gif 文件大小 nsdata确定
            if (isGIF) {

                [[TZImageManager manager] getOriginalPhotoDataWithAsset:assets[0] completion:^(NSData *data, NSDictionary *info, BOOL isDegraded) {

                    NSLog(@"gif file check pass,filename==%@", [assets[0] valueForKey:@"filename"]);

                    NSLog(@"gif file length %d", [data length]);

                    // 保存gif 文件
                    NSString *path = [self getImagePath];


                    if ([data writeToFile:path atomically:YES]) {

                        NSLog(@"gif file save success................");

                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (self.callback) {

                                NSMutableDictionary *dataDic = [[NSMutableDictionary alloc] init];

                                [dataDic setValue:@"true" forKey:@"isGif"];
                                [dataDic setValue:@([data length] / 1024) forKey:@"howBig"];
                                [dataDic setValue:@(fixelW) forKey:@"width"];
                                [dataDic setValue:@(fixelH) forKey:@"height"];

                                NSDictionary *backData = [NSDictionary configCallbackDataWithResCode:BMResCodeSuccess msg:nil data:dataDic];
                                NSLog(@"gif file save success2 backData===%@", backData);
                                self.callback(backData);
                            }
                        });


                    } else {
                        NSLog(@"gif file save error................");
                        NSLog(@"gif file save error................");
                        NSLog(@"gif file save error................");
                        NSLog(@"gif file save error................");
                        NSLog(@"gif file save error................");

                    }
                }];
            } else {
                // jpeg || png
//                [weakSelf cacheImages:photos];
                [weakSelf cacheImagesPlus:photos assets:assets];
            }

        } else {
            [weakSelf uploadImage:photos];
        }
    }];

    imagePickerVc.modalPresentationStyle = UIModalPresentationFullScreen;

    [self.weexInstance.viewController presentViewController:imagePickerVc animated:YES completion:nil];

}

//拍照
- (void)takePhoto {

    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusRestricted || authStatus == AVAuthorizationStatusDenied) {
        // 无相机权限 做一个友好的提示
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"无法使用相机" message:@"请在iPhone的""设置-隐私-相机""中允许访问相机" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"设置", nil];
        [alert show];
        // 拍照之前还需要检查相册权限
    } else if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusDenied) { // 已被拒绝，没有相册权限，将无法保存拍的照片
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"无法访问相册" message:@"请在iPhone的""设置-隐私-相册""中允许访问相册" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"设置", nil];
        alert.tag = 1;
        [alert show];
    } else { // 调用相机
        //资源类型为照相机
        UIImagePickerControllerSourceType sourceType = UIImagePickerControllerSourceTypeCamera;
        //判断是否有相机
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.delegate = self;
            /* 判断是否是上传头像如果是则 允许裁剪图片 */
            if (self.imageInfo.allowCrop) picker.allowsEditing = YES;
            //资源类型为照相机
            picker.sourceType = sourceType;
            [self.weexInstance.viewController presentViewController:picker animated:YES completion:nil];

        } else {
            WXLogInfo(@"该设备无摄像头");
        }
    }
}

- (void)saveImage:(UIImage *)image {

    if (!image) {
        return;
    }
    // 图片保存到系统相册
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized || [PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        }                                 completionHandler:nil];
    }

    @weakify(self);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        @strongify(self);
//        CGSize asize = CGSizeMake(self.imageInfo.imageWidth, self.imageInfo.imageWidth * image.size.height / image.size.width);
//
//        UIImage *smallImage = [image imageToSize:asize];
//
//        if (!smallImage) {
//            WXLogError(@"图片不存在");
//            return;
//        }

        dispatch_async(dispatch_get_main_queue(), ^{

            if (self.isLocal) {
                //缓存图片到本地
                [self cacheImages:@[image]];
            } else {
                //上传服务器
                [self uploadImage:@[image]];
            }

        });

    });
}

/** 将图片缓存到磁盘 */
- (void)cacheImages:(NSArray<UIImage *> *)images {
    @weakify(self);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @strongify(self);
        NSMutableArray *imagesPath = [[NSMutableArray alloc] init];
        for (UIImage *img in images) {

            NSString *path = [self saveImage2Disk:img];
            [imagesPath addObject:path];
        }


        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.callback) {

                NSDictionary *backData = [NSDictionary configCallbackDataWithResCode:BMResCodeSuccess msg:nil data:imagesPath];

                self.callback(backData);
            }
        });
    });
}


/** 将图片缓存到磁盘 */
- (void)cacheImagesPlus:(NSArray<UIImage *> *)images assets:(NSArray *)assets {
    @weakify(self);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @strongify(self);
        NSMutableArray *imagesPath = [[NSMutableArray alloc] init];
        for (UIImage *img in images) {
            // todo check gif , if the gif is too big , please do not save it
            // and then return home;
            NSString *path = [self saveImage2Disk:img];
            [imagesPath addObject:path];
        }


        CGFloat fixelW = CGImageGetWidth(images[0].CGImage);
        CGFloat fixelH = CGImageGetHeight(images[0].CGImage);

        [[TZImageManager manager] getOriginalPhotoDataWithAsset:assets[0] completion:^(NSData *data, NSDictionary *info, BOOL isDegraded) {

            NSLog(@"jpeg file length %d", [data length]);

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.callback) {

                    NSMutableDictionary *dataDic = [[NSMutableDictionary alloc] init];
                    [dataDic setValue:@"false" forKey:@"isGif"];
                    [dataDic setValue:@([data length] / 1024) forKey:@"howBig"];
                    [dataDic setValue:@(fixelW) forKey:@"width"];
                    [dataDic setValue:@(fixelH) forKey:@"height"];

                    NSDictionary *backData = [NSDictionary configCallbackDataWithResCode:BMResCodeSuccess msg:nil data:dataDic];
                    NSLog(@"jepg | png  file save success2 backData===%@", backData);
                    NSLog(@"backData===%@", backData);
                    self.callback(backData);
                }
            });


        }];

    });
}

#pragma mark - Custom Delegate & DataSource


#pragma mark - System Delegate & DataSource

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {

    if (buttonIndex == 1) {
        [self LocalPhoto];
    } else if (buttonIndex == 0) {
        [self takePhoto];
    }

}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) { // 去设置界面，开启相机访问权限
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    if ([[info objectForKey:UIImagePickerControllerMediaType] isEqualToString:(__bridge NSString *) kUTTypeImage]) {
        UIImage *img = [info objectForKey:UIImagePickerControllerEditedImage];
        if (!img) img = [info objectForKey:UIImagePickerControllerOriginalImage];

        [self saveImage:img];
    }

    [picker dismissViewControllerAnimated:YES completion:nil];
}

//------------------------------------------------------------------------------------
#pragma mark - 将图片保存到本地

//------------------------------------------------------------------------------------
//获取当前时间字符串
- (NSString *)getCurrentTimeString {
    return [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] * 1000];
}

#pragma mark ---------图片管理-----------

//获取图片完整路径
- (NSString *)getImagePath {

    NSString *path = NSHomeDirectory();
    //path = [path stringByAppendingPathComponent:@"Library/Bundlejs/bundle/assets/cropper/images"];
    path = [path stringByAppendingPathComponent:@"Library/Caches/images"];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:path]) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }


    NSString *filePath = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", @"cropper"]];
    //NSString *filePath = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg",[self getCurrentTimeString]]];

    BOOL isSuccess = [fm removeItemAtPath:filePath error:nil];
    NSLog(@"filepath|%@, %@", filePath, isSuccess ? @"删除成功" : @"删除失败");

    NSLog(@"filePath====%@", filePath);

    return filePath;
}

//图片保存本地
- (NSString *)saveImage2Disk:(UIImage *)tempImage {

    NSLog(@"====================================saveImage2Disk===================================");
    NSLog(@"====================================saveImage2Disk===================================");
    NSLog(@"====================================saveImage2Disk===================================");
    NSData *imageData = UIImageJPEGRepresentation(tempImage, 0.8);
    NSString *path = [self getImagePath];
    if ([imageData writeToFile:path atomically:YES]) {
        return path;
    }
    return @"";
}

#pragma mark - Public Method

- (void)uploadImageWithInfo:(BMUploadImageModel *)info weexInstance:(WXSDKInstance *)weexInstance callback:(WXModuleCallback)callback {
    self.isLocal = NO;
    self.imageInfo = info;
    self.weexInstance = weexInstance;
    self.callback = callback;
    [self selectImage];
}

- (void)uploadImage:(NSArray *)images uploadImageModel:(BMUploadImageModel *)info callback:(WXModuleCallback)callback {
    self.isLocal = NO;
    self.callback = callback;
    self.imageInfo = info;

    @weakify(self);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @strongify(self);
        NSMutableArray *imgs = [[NSMutableArray alloc] initWithCapacity:images.count];
        for (id item in images) {
            if ([item isKindOfClass:[UIImage class]]) {
                [imgs addObject:item];
            } else if ([item isKindOfClass:[NSString class]]) {
                NSString *imgPath = (NSString *) item;
                if ([imgPath hasPrefix:BM_LOCAL]) {
                    // 拦截器
                    if (BM_InterceptorOn()) {
                        NSURL *imgUrl = [NSURL URLWithString:imgPath];
                        // 从jsbundle读取图片
                        NSString *imgPath = [NSString stringWithFormat:@"%@/%@%@", K_JS_PAGES_PATH, imgUrl.host, imgUrl.path];
                        UIImage *img = [UIImage imageWithContentsOfFile:imgPath];

                        if (img) {
                            [imgs addObject:img];
                        } else {
                            WXLogError(@"加载jsbundle中图片失败:%@", imgPath);
                        }

                    } else {
                        WXLogError(@"拦截器关闭状态下不支持上传jsbundle中的图片");
                    }
                } else if (![imgPath hasPrefix:@"http"]) {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    if ([fm fileExistsAtPath:imgPath]) {
                        UIImage *img = [UIImage imageWithContentsOfFile:imgPath];
                        if (img) {
                            [imgs addObject:img];
                        } else {
                            WXLogError(@"加载本地图片失败：%@", imgPath);
                        }
                    } else {
                        WXLogError(@"本地图片不存在：%@", imgPath);
                    }
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self uploadImage:imgs];
        });
    });
}

- (void)camera:(BMUploadImageModel *)info weexInstance:(WXSDKInstance *)weexInstance callback:(WXModuleCallback)callback {
    self.isLocal = YES;
    self.imageInfo = info;
    self.callback = callback;
    self.weexInstance = weexInstance;
    [self takePhoto];
}

- (void)pick:(BMUploadImageModel *)info weexInstance:(WXSDKInstance *)weexInstance callback:(WXModuleCallback)callback {
    self.isLocal = YES;
    self.imageInfo = info;
    self.callback = callback;
    self.weexInstance = weexInstance;
    [self LocalPhoto];
}

@end
