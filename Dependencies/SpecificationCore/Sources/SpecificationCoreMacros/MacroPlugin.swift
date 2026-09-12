//
//  MacroPlugin.swift
//  SpecificationCore
//
//  Registers macros for the SpecificationCore macro plugin target.
//
//  Created by AutoContext Macro Implementation.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SpecificationCorePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SpecsMacro.self,
        AutoContextMacro.self
    ]
}
