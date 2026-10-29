//
//  SensitiveField.h
//  VOpenKey AI, portable
//
//  Does the name of a text field say that a secret is typed there (a password, a PIN, a one-time code)? The platform reads the
//  names a program gives the field (macOS: Accessibility, Windows: UI Automation) and asks here. The suggestion bar must not show
//  what is typed into such a field, nor learn it. macOS has the same list in SensitiveField.m (it reads Accessibility itself).
//  ASCII-only source.
//
#pragma once
#include <string>

namespace vsuggest {

/** UTF-8 text: the placeholder, title, help text or identifier of a field. Case, accents and a decomposed form do not matter. */
bool namesASecret(const std::string& utf8);

} // namespace vsuggest
