# Test Steps

## Table of Contents

* [Introduction](#introduction)
* [Test Step Summary](#test-step-summary)
* [Details](#details)
  * [assert_firebase_value](#assert_firebase_document)
  * [set_firebase_value](#set_firebase_value)


## Introduction

This plugin provides a few new [Test Steps](https://github.com/peiffer-innovations/automated_testing_framework/blob/main/documentation/STEPS.md) related to Firebase Realtime Database actions.

The included steps will get the `FirebaseDatabase` reference from the `TestFirebaseHelper`.  If you would like the test steps to use a different reference than the application's default, you can set the `firebase` property to the reference the test steps should use instead.

The `TestFirebaseHelper` also provides a mechanism to register the steps supported by this plugin via the `TestFirebaseHelper.registerTestSteps` function.  That will place the custom steps on the registry for use within your application.

---

## Test Step Summary

Test Step IDs                                     | Description
--------------------------------------------------|-------------
[assert_firebase_value](#assert_firebase_value) | Asserts the value on the Firebase document equals the `value`.
[set_firebase_value](#set_firebase_value)       | Sets the value on the Firebase document to the `value`.


---
## Details


### assert_firebase_value

**How it Works**

1. Attempts to find the Document with the given `path`; fails if not found.
2. Gets the data from the Document, encodes it as a JSON string then compares it to the `value`.  This will fail if one of the follosing is true:
    1. The `equals` is `true` or undefined and the Document's value does not match the `value`.
    2. The `equals` is `false` Document's value does match the `error`.


**Example**

```json
{
  "id": "assert_firebase_value",
  "image": "<optional_base_64_image>",
  "values": {
    "equals": true,
    "path": "my/firebase/path",
    "value": "{\"foo\":\"bar\"}"
  }
}
```

**Values**

Key      | Type    | Required | Supports Variable | Description
---------|---------|----------|-------------------|-------------
`equals` | boolean | No       | No                | Defines whether the Document's value must equal the `value` or must not equal the `value`.  Defaults to `true` if not defined.
`path`   | String  | Yes      | Yes               | The `path` to the Document. 
`value`  | String  | Yes      | Yes               | The value to evaluate against.


---

### set_firebase_value

**How it Works**

1. JSON decodes the `value` into a Map object.
2. Attempts to set the value of the Document with `path` to the decoded Map; fails if unable to.

**Example**

```json
{
  "id": "set_firebase_value",
  "image": "<optional_base_64_image>",
  "values": {
    "path": "my/firebase/path",
    "value": "{\"foo\":\"bar\"}"
  }
}
```

**Values**

Key     | Type    | Required | Supports Variable | Description
--------|---------|----------|-------------------|-------------
`path`  | String  | Yes      | Yes               | The `path` of the Firebase Document to check.
`value` | String  | Yes      | Yes               | The String-encoded JSON value to set to the Document.
