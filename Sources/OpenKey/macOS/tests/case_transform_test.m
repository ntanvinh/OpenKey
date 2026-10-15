//
//  case_transform_test.m
//  Tests of CaseTransform: Unicode case rules, word cutting, the list the bar offers.
//
#import <Foundation/Foundation.h>
#import "CaseTransform.h"

static int failures = 0;

static void Check(VOKCaseStyle style, NSString* input, NSString* expected) {
    NSString* got = [CaseTransform apply:style toText:input];
    if (![got isEqualToString:expected]) {
        failures++;
        printf("FAIL %s: [%s] -> [%s], expected [%s]\n", [CaseTransform nameOfStyle:style].UTF8String, input.UTF8String,
               got.UTF8String, expected.UTF8String);
    }
}

int main(void) {
    @autoreleasepool {
        //Vietnamese, precomposed
        Check(VOKCaseUpper, @"xin chào thế giới", @"XIN CHÀO THẾ GIỚI");
        Check(VOKCaseLower, @"XIN CHÀO THẾ GIỚI Đà Nẵng", @"xin chào thế giới đà nẵng");
        Check(VOKCaseUpper, @"đường", @"ĐƯỜNG");
        Check(VOKCaseTitle, @"xin chào thế giới", @"Xin Chào Thế Giới");
        Check(VOKCaseTitle, @"XIN CHÀO ĐÀ NẴNG", @"Xin Chào Đà Nẵng");
        Check(VOKCaseTitle, @"don't stop well-known", @"Don't Stop Well-Known");
        Check(VOKCaseTitle, @"line one\nline two", @"Line One\nLine Two");
        //Vietnamese written with separate accents (NFD) keeps working
        NSString* nfd = [@"xin chào" decomposedStringWithCanonicalMapping];
        Check(VOKCaseUpper, nfd, [@"XIN CHÀO" decomposedStringWithCanonicalMapping]);
        Check(VOKCaseTitle, nfd, [@"Xin Chào" decomposedStringWithCanonicalMapping]);
        Check(VOKCaseStripMarks, nfd, @"xin chao");
        //other scripts
        Check(VOKCaseUpper, @"straße", @"STRASSE");
        Check(VOKCaseUpper, @"привет мир", @"ПРИВЕТ МИР");
        Check(VOKCaseLower, @"ΟΔΥΣΣΕΥΣ", @"οδυσσευς");            //final sigma
        Check(VOKCaseTitle, @"привет мир", @"Привет Мир");
        Check(VOKCaseUpper, @"日本語 abc", @"日本語 ABC");        //no case: untouched
        Check(VOKCaseUpper, @"😀 ok", @"😀 OK");
        Check(VOKCaseTitle, @"élan vital ñandú", @"Élan Vital Ñandú");
        //sentence case
        Check(VOKCaseSentence, @"XIN CHÀO. TÔI LÀ VINH! bạn khỏe không? tốt", @"Xin chào. Tôi là vinh! Bạn khỏe không? Tốt");
        Check(VOKCaseSentence, @"giá là 3.14 usd. xem vinh.com ngay", @"Giá là 3.14 usd. Xem vinh.com ngay");
        Check(VOKCaseSentence, @"dòng một\ndòng hai", @"Dòng một\nDòng hai");
        Check(VOKCaseSentence, @"1. đầu tiên. 2. thứ hai", @"1. Đầu tiên. 2. Thứ hai");
        Check(VOKCaseSentence, @"\"đã xong\" rồi", @"\"Đã xong\" rồi");
        Check(VOKCaseSentence, @"  đã xong", @"  Đã xong");
        //names
        Check(VOKCaseCamel, @"xin chào thế giới", @"xinChàoThếGiới");
        Check(VOKCasePascal, @"xin chào thế giới", @"XinChàoThếGiới");
        Check(VOKCaseSnake, @"Xin chào thế giới", @"xin_chào_thế_giới");
        Check(VOKCaseKebab, @"Xin chào thế giới", @"xin-chào-thế-giới");
        Check(VOKCaseConstant, @"Xin chào thế giới", @"XIN_CHÀO_THẾ_GIỚI");
        Check(VOKCaseSnake, @"myVariableName", @"my_variable_name");
        Check(VOKCaseCamel, @"my_variable_name", @"myVariableName");
        Check(VOKCaseKebab, @"HTMLParser", @"html-parser");
        Check(VOKCaseSnake, @"XMLHttpRequest2Go", @"xml_http_request2_go");
        Check(VOKCasePascal, @"user-id  number", @"UserIdNumber");
        Check(VOKCaseConstant, @"max.retry.count", @"MAX_RETRY_COUNT");
        Check(VOKCaseSnake, @"  indented line  ", @"  indented_line  ");
        Check(VOKCaseSnake, @"first line\n  second Line\r\nthird", @"first_line\n  second_line\r\nthird");
        Check(VOKCaseSnake, @"!!! ???", @"!!! ???");          //no words: as it is
        Check(VOKCaseCamel, @"привет мир", @"приветМир");
        Check(VOKCaseSnake, @"ĐàNẵng", @"đà_nẵng");
        Check(VOKCaseSnake, nfd, [@"xin_chào" decomposedStringWithCanonicalMapping]);
        //without accents
        Check(VOKCaseStripMarks, @"Xin chào thế giới, Đà Nẵng đẹp quá! Ơ Ư ơ ư", @"Xin chao the gioi, Da Nang dep qua! O U o u");
        Check(VOKCaseStripMarks, @"Ångström Łódź Øl café", @"Angstrom Lodz Ol cafe");
        Check(VOKCaseStripMarks, @"ไทย हिन्दी", @"ไทย हिन्दी");  //marks of other scripts are letters
        Check(VOKCaseSlug, @"Xin chào, Thế giới! Đà Nẵng 2026", @"xin-chao-the-gioi-da-nang-2026");
        Check(VOKCaseSlug, @"  iPhone 15 Pro  ", @"  iphone-15-pro  ");
        //empty and tiny
        Check(VOKCaseUpper, @"", @"");
        Check(VOKCaseTitle, @"a", @"A");
        Check(VOKCaseSentence, @"é", @"É");

        //what the bar offers
        NSArray* offers = [CaseTransform offersForText:@"hello"];
        NSMutableArray* names = [NSMutableArray array];
        for (NSDictionary* o in offers) [names addObject:o[@"name"]];
        NSArray* want = @[@"CHỮ HOA", @"Viết Hoa Từng Từ"];
        if (![names isEqualToArray:want]) { failures++; printf("FAIL offers hello: %s\n", names.description.UTF8String); }
        offers = [CaseTransform offersForText:@"Xin chào thế giới"];
        if (offers.count != 10) { failures++; printf("FAIL offers count %lu: %s\n", (unsigned long)offers.count, offers.description.UTF8String); }
        if (![offers.firstObject[@"name"] isEqualToString:@"CHỮ HOA"]) { failures++; printf("FAIL order\n"); }
        offers = [CaseTransform offersForText:@"123"];
        if (offers.count != 0) { failures++; printf("FAIL offers digits: %s\n", offers.description.UTF8String); }
        offers = [CaseTransform offersForText:@"XIN"];
        names = [NSMutableArray array];
        for (NSDictionary* o in offers) [names addObject:o[@"name"]];
        printf("offers XIN: %s\n", [names componentsJoinedByString:@", "].UTF8String);

        //a long text must not be slow
        NSMutableString* big = [NSMutableString string];
        for (int i = 0; i < 2000; i++) [big appendString:@"Xin chào thế giới. "];
        NSDate* t = [NSDate date];
        for (NSNumber* s in [CaseTransform stylesByPopularity]) [CaseTransform apply:(VOKCaseStyle)s.integerValue toText:big];
        printf("11 styles on (38k chars is the most the bar previews) %lu chars: %.2f s\n", (unsigned long)big.length, -[t timeIntervalSinceNow]);
    }
    printf(failures == 0 ? "ALL OK\n" : "%d FAILURES\n", failures);
    return failures != 0;
}
