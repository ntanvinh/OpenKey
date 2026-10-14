//
//  SmartSwitchKey.h
//  OpenKey
//
//  Created by Tuyen on 8/13/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#ifndef SmartSwitchKey_h
#define SmartSwitchKey_h

#include "DataType.h"
#include <string>
#include <utility>
#include <vector>

using namespace std;

void initSmartSwitchKey(const Byte* pData, const int& size);

/**
 * convert all data to save on disk
 */
void getSmartSwitchKeySaveData(vector<Byte>& outData);

/**
 * find and get language input method, if don't has set @currentInputMethod value for this app
 * return:
 * -1: don't have this bundleId
 * 0: English
 * 1: Vietnamese
 */
int getAppInputMethodStatus(const string& bundleId, const int& currentInputMethod);

/**
 * Set default language for this @bundleId
 * (the value is the language, 0 or 1, plus the code table times two: what the apps remember is `language | (codeTable << 1)`)
 */
void setAppInputMethodStatus(const string& bundleId, const int& language);

/**
 * Everything that was remembered, for showing and editing it: application and value as above
 */
void getAllAppInputMethodStatus(vector<pair<string, int> >& out);

/**
 * Forget an application: the next time it is used it is remembered again, from what is selected then
 */
void removeAppInputMethodStatus(const string& bundleId);

#endif /* SmartSwitchKey_h */
