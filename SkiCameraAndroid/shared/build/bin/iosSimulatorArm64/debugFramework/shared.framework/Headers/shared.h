#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

@class SharedRect, SharedPoint, SharedRectCompanion;

NS_ASSUME_NONNULL_BEGIN
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunknown-warning-option"
#pragma clang diagnostic ignored "-Wincompatible-property-type"
#pragma clang diagnostic ignored "-Wnullability"

#pragma push_macro("_Nullable_result")
#if !__has_feature(nullability_nullable_result)
#undef _Nullable_result
#define _Nullable_result _Nullable
#endif

__attribute__((swift_name("KotlinBase")))
@interface SharedBase : NSObject
- (instancetype)init __attribute__((unavailable));
+ (instancetype)new __attribute__((unavailable));
+ (void)initialize __attribute__((objc_requires_super));
@end

@interface SharedBase (SharedBaseCopying) <NSCopying>
@end

__attribute__((swift_name("KotlinMutableSet")))
@interface SharedMutableSet<ObjectType> : NSMutableSet<ObjectType>
@end

__attribute__((swift_name("KotlinMutableDictionary")))
@interface SharedMutableDictionary<KeyType, ObjectType> : NSMutableDictionary<KeyType, ObjectType>
@end

@interface NSError (NSErrorSharedKotlinException)
@property (readonly) id _Nullable kotlinException;
@end

__attribute__((swift_name("KotlinNumber")))
@interface SharedNumber : NSNumber
- (instancetype)initWithChar:(char)value __attribute__((unavailable));
- (instancetype)initWithUnsignedChar:(unsigned char)value __attribute__((unavailable));
- (instancetype)initWithShort:(short)value __attribute__((unavailable));
- (instancetype)initWithUnsignedShort:(unsigned short)value __attribute__((unavailable));
- (instancetype)initWithInt:(int)value __attribute__((unavailable));
- (instancetype)initWithUnsignedInt:(unsigned int)value __attribute__((unavailable));
- (instancetype)initWithLong:(long)value __attribute__((unavailable));
- (instancetype)initWithUnsignedLong:(unsigned long)value __attribute__((unavailable));
- (instancetype)initWithLongLong:(long long)value __attribute__((unavailable));
- (instancetype)initWithUnsignedLongLong:(unsigned long long)value __attribute__((unavailable));
- (instancetype)initWithFloat:(float)value __attribute__((unavailable));
- (instancetype)initWithDouble:(double)value __attribute__((unavailable));
- (instancetype)initWithBool:(BOOL)value __attribute__((unavailable));
- (instancetype)initWithInteger:(NSInteger)value __attribute__((unavailable));
- (instancetype)initWithUnsignedInteger:(NSUInteger)value __attribute__((unavailable));
+ (instancetype)numberWithChar:(char)value __attribute__((unavailable));
+ (instancetype)numberWithUnsignedChar:(unsigned char)value __attribute__((unavailable));
+ (instancetype)numberWithShort:(short)value __attribute__((unavailable));
+ (instancetype)numberWithUnsignedShort:(unsigned short)value __attribute__((unavailable));
+ (instancetype)numberWithInt:(int)value __attribute__((unavailable));
+ (instancetype)numberWithUnsignedInt:(unsigned int)value __attribute__((unavailable));
+ (instancetype)numberWithLong:(long)value __attribute__((unavailable));
+ (instancetype)numberWithUnsignedLong:(unsigned long)value __attribute__((unavailable));
+ (instancetype)numberWithLongLong:(long long)value __attribute__((unavailable));
+ (instancetype)numberWithUnsignedLongLong:(unsigned long long)value __attribute__((unavailable));
+ (instancetype)numberWithFloat:(float)value __attribute__((unavailable));
+ (instancetype)numberWithDouble:(double)value __attribute__((unavailable));
+ (instancetype)numberWithBool:(BOOL)value __attribute__((unavailable));
+ (instancetype)numberWithInteger:(NSInteger)value __attribute__((unavailable));
+ (instancetype)numberWithUnsignedInteger:(NSUInteger)value __attribute__((unavailable));
@end

__attribute__((swift_name("KotlinByte")))
@interface SharedByte : SharedNumber
- (instancetype)initWithChar:(char)value;
+ (instancetype)numberWithChar:(char)value;
@end

__attribute__((swift_name("KotlinUByte")))
@interface SharedUByte : SharedNumber
- (instancetype)initWithUnsignedChar:(unsigned char)value;
+ (instancetype)numberWithUnsignedChar:(unsigned char)value;
@end

__attribute__((swift_name("KotlinShort")))
@interface SharedShort : SharedNumber
- (instancetype)initWithShort:(short)value;
+ (instancetype)numberWithShort:(short)value;
@end

__attribute__((swift_name("KotlinUShort")))
@interface SharedUShort : SharedNumber
- (instancetype)initWithUnsignedShort:(unsigned short)value;
+ (instancetype)numberWithUnsignedShort:(unsigned short)value;
@end

__attribute__((swift_name("KotlinInt")))
@interface SharedInt : SharedNumber
- (instancetype)initWithInt:(int)value;
+ (instancetype)numberWithInt:(int)value;
@end

__attribute__((swift_name("KotlinUInt")))
@interface SharedUInt : SharedNumber
- (instancetype)initWithUnsignedInt:(unsigned int)value;
+ (instancetype)numberWithUnsignedInt:(unsigned int)value;
@end

__attribute__((swift_name("KotlinLong")))
@interface SharedLong : SharedNumber
- (instancetype)initWithLongLong:(long long)value;
+ (instancetype)numberWithLongLong:(long long)value;
@end

__attribute__((swift_name("KotlinULong")))
@interface SharedULong : SharedNumber
- (instancetype)initWithUnsignedLongLong:(unsigned long long)value;
+ (instancetype)numberWithUnsignedLongLong:(unsigned long long)value;
@end

__attribute__((swift_name("KotlinFloat")))
@interface SharedFloat : SharedNumber
- (instancetype)initWithFloat:(float)value;
+ (instancetype)numberWithFloat:(float)value;
@end

__attribute__((swift_name("KotlinDouble")))
@interface SharedDouble : SharedNumber
- (instancetype)initWithDouble:(double)value;
+ (instancetype)numberWithDouble:(double)value;
@end

__attribute__((swift_name("KotlinBoolean")))
@interface SharedBoolean : SharedNumber
- (instancetype)initWithBool:(BOOL)value;
+ (instancetype)numberWithBool:(BOOL)value;
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("AutoZoomManager")))
@interface SharedAutoZoomManager : SharedBase
- (instancetype)init __attribute__((swift_name("init()"))) __attribute__((objc_designated_initializer));
+ (instancetype)new __attribute__((availability(swift, unavailable, message="use object initializers instead")));
- (void)tuneKp:(SharedDouble * _Nullable)kp kd:(SharedDouble * _Nullable)kd alpha:(SharedDouble * _Nullable)alpha __attribute__((swift_name("tune(kp:kd:alpha:)")));
- (SharedRect *)updateSkierRect:(SharedRect *)skierRect dt:(double)dt __attribute__((swift_name("update(skierRect:dt:)")));
@property double maxPanSpeed __attribute__((swift_name("maxPanSpeed")));
@property double maxZoomSpeed __attribute__((swift_name("maxZoomSpeed")));
@property double targetSubjectHeightRatio __attribute__((swift_name("targetSubjectHeightRatio")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("PIDController")))
@interface SharedPIDController : SharedBase
- (instancetype)initWithKp:(double)kp kd:(double)kd __attribute__((swift_name("init(kp:kd:)"))) __attribute__((objc_designated_initializer));
- (void)reset __attribute__((swift_name("reset()")));
- (double)updateError:(double)error dt:(double)dt __attribute__((swift_name("update(error:dt:)")));
@property double kd __attribute__((swift_name("kd")));
@property double kp __attribute__((swift_name("kp")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("Point")))
@interface SharedPoint : SharedBase
- (instancetype)initWithX:(double)x y:(double)y __attribute__((swift_name("init(x:y:)"))) __attribute__((objc_designated_initializer));
- (SharedPoint *)doCopyX:(double)x y:(double)y __attribute__((swift_name("doCopy(x:y:)")));
- (BOOL)isEqual:(id _Nullable)other __attribute__((swift_name("isEqual(_:)")));
- (NSUInteger)hash __attribute__((swift_name("hash()")));
- (NSString *)description __attribute__((swift_name("description()")));
@property (readonly) double x __attribute__((swift_name("x")));
@property (readonly) double y __attribute__((swift_name("y")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("Rect")))
@interface SharedRect : SharedBase
- (instancetype)initWithLeft:(double)left top:(double)top right:(double)right bottom:(double)bottom __attribute__((swift_name("init(left:top:right:bottom:)"))) __attribute__((objc_designated_initializer));
@property (class, readonly, getter=companion) SharedRectCompanion *companion __attribute__((swift_name("companion")));
- (SharedRect *)doCopyLeft:(double)left top:(double)top right:(double)right bottom:(double)bottom __attribute__((swift_name("doCopy(left:top:right:bottom:)")));
- (BOOL)isEqual:(id _Nullable)other __attribute__((swift_name("isEqual(_:)")));
- (NSUInteger)hash __attribute__((swift_name("hash()")));
- (NSString *)description __attribute__((swift_name("description()")));
@property (readonly) double bottom __attribute__((swift_name("bottom")));
@property (readonly) SharedPoint *center __attribute__((swift_name("center")));
@property (readonly) double centerX __attribute__((swift_name("centerX")));
@property (readonly) double centerY __attribute__((swift_name("centerY")));
@property (readonly) double height __attribute__((swift_name("height")));
@property (readonly) double left __attribute__((swift_name("left")));
@property (readonly) double right __attribute__((swift_name("right")));
@property (readonly) double top __attribute__((swift_name("top")));
@property (readonly) double width __attribute__((swift_name("width")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("Rect.Companion")))
@interface SharedRectCompanion : SharedBase
+ (instancetype)alloc __attribute__((unavailable));
+ (instancetype)allocWithZone:(struct _NSZone *)zone __attribute__((unavailable));
+ (instancetype)companion __attribute__((swift_name("init()")));
@property (class, readonly, getter=shared) SharedRectCompanion *shared __attribute__((swift_name("shared")));
- (SharedRect *)fromLTRBLeft:(double)left top:(double)top right:(double)right bottom:(double)bottom __attribute__((swift_name("fromLTRB(left:top:right:bottom:)")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("SmoothingFilter")))
@interface SharedSmoothingFilter : SharedBase
- (instancetype)initWithAlpha:(double)alpha __attribute__((swift_name("init(alpha:)"))) __attribute__((objc_designated_initializer));
- (SharedDouble * _Nullable)currentValue __attribute__((swift_name("currentValue()")));
- (double)filterRawValue:(double)rawValue __attribute__((swift_name("filter(rawValue:)")));
- (void)reset __attribute__((swift_name("reset()")));
@property double alpha __attribute__((swift_name("alpha")));
@end

#pragma pop_macro("_Nullable_result")
#pragma clang diagnostic pop
NS_ASSUME_NONNULL_END
