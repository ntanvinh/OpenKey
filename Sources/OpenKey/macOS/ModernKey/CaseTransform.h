//
//  CaseTransform.h
//  VOpenKey
//
//  Changes the case of a text: CHỮ HOA, chữ thường, Viết Hoa Từng Từ, camelCase... Unicode all the way: Vietnamese (precomposed
//  or with separate accents), Greek, Cyrillic and the rest follow the case rules of the system (ICU), ß becomes SS, a final
//  Greek sigma is ς. Pure Foundation, no windows: the case bar and the tests use it.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, VOKCaseStyle) {
    VOKCaseUpper,        //XIN CHÀO THẾ GIỚI
    VOKCaseLower,        //xin chào thế giới
    VOKCaseTitle,        //Xin Chào Thế Giới
    VOKCaseSentence,     //Xin chào thế giới. Tôi là Vinh.
    VOKCaseCamel,        //xinChàoThếGiới
    VOKCasePascal,       //XinChàoThếGiới
    VOKCaseSnake,        //xin_chào_thế_giới
    VOKCaseKebab,        //xin-chào-thế-giới
    VOKCaseConstant,     //XIN_CHÀO_THẾ_GIỚI
    VOKCaseStripMarks,   //Xin chao the gioi
    VOKCaseSlug          //xin-chao-the-gioi
};

@interface CaseTransform : NSObject

/// Every style, the one people use most first.
+(NSArray<NSNumber*>*)stylesByPopularity;

/// What the style is called on the bar. It is written the way it works: "CHỮ HOA", "camelCase".
+(NSString*)nameOfStyle:(VOKCaseStyle)style;

/// The text in that style. A text without letters comes back as it is. The styles that make one name out of the text (camelCase,
/// snake_case...) work on one line at a time and keep the line breaks and the spaces at both ends of a line.
+(NSString*)apply:(VOKCaseStyle)style toText:(NSString*)text;

/// The styles that do something to the text and the text they give, most popular first. A style whose result another style, more
/// popular, already gives is left out ("hello": Title Case and PascalCase are the same).
+(NSArray<NSDictionary*>*)offersForText:(NSString*)text;

@end
