import Foundation
import RuriCore

/// JSON Schema for the command boundary, independent of Swift's persistence
/// encoding. Payload properties are additive within schemaVersion 1.
package enum CommandSchemas {
    package static let string: Value = .object(["type": .string("string")])
    package static let boolean: Value = .object(["type": .string("boolean")])
    package static let number: Value = .object(["type": .string("number")])
    package static let integer: Value = .object(["type": .string("integer")])
    static let null: Value = .object(["type": .string("null")])
    package static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(Value.string)), "additionalProperties": .bool(true)])
    }
    package static func array(_ item: Value) -> Value { .object(["type": .string("array"), "items": item]) }
    package static func nullable(_ value: Value) -> Value { .object(["anyOf": .array([value, null])]) }
    package static func page(_ item: Value) -> Value { object(["items": array(item), "total": integer, "offset": integer, "hasMore": boolean, "issues": array(object([:]))]) }
    static func fields(_ names: String, type: Value = string) -> [String: Value] { Dictionary(uniqueKeysWithValues: names.split(separator: ",").map { (String($0), type) }) }
    static let instance = object(fields("id,name,gameVersion,directoryID,runDirectory,instanceDirectory,gameDirectory,iconGlyph,iconTint,issue", type: nullable(string))
        .merging(["installed": boolean, "favorite": boolean, "hasCustomIcon": boolean, "components": array(object(fields("loader,version")))]) { _, new in new })
    static let account = object(fields("id,kind,username,uuid,server", type: nullable(string)))
    static let session = object(fields("id,instanceID,instanceName,state,stage,createdAt,activity,failure", type: nullable(string))
        .merging(["finished": boolean, "playedSeconds": number, "gameExitCode": nullable(integer), "trackingVersion": nullable(integer),
                   "segments": array(object(["id": string, "kind": string, "target": string, "name": string, "startedAt": string, "endedAt": string, "seconds": number, "quality": string, "source": string]))]) { _, new in new })
    static let project = object(fields("id,provider,title,type,pageURL", type: nullable(string)))
    static let version = object(fields("id,name,number,channel,publishedAt,filename").merging(["gameVersions": array(string), "loaders": array(string), "bytes": integer]) { _, new in new })
    static let managed = object(fields("id,provider,projectID,versionID,title,version,filename").merging(["enabled": boolean, "bytes": integer]) { _, new in new })
    static let content = object(fields("filename,title,version,kind", type: nullable(string)).merging(["enabled": boolean, "bytes": integer, "managed": nullable(managed)]) { _, new in new })
    static let world = object(fields("folder,name,version,lastPlayed,error", type: nullable(string)).merging(["gameType": nullable(integer), "bytes": nullable(integer), "hardcore": boolean]) { _, new in new })
    static let backup = object(fields("id,world,worldName,createdAt", type: nullable(string)).merging(["bytes": integer]) { _, new in new })
    static let schematic = object(["path": string, "directory": boolean, "bytes": integer, "modifiedAt": nullable(string)])
    static let directory = object(fields("id,name,path,layout").merging(["detached": boolean, "available": boolean]) { _, new in new })
    static let java = object(fields("id,path,version,architecture,vendor", type: nullable(string)).merging(["major": integer]) { _, new in new })
    static let configReport = object(["scope": string, "revision": nullable(string), "explicit": .object([:]), "effective": .object([:]), "sources": object([:]), "key": string, "source": nullable(string)])
    static let installation = object(fields("executable,link,target,legacyLink,packageManager", type: nullable(string)).merging(["installed": boolean, "owned": boolean, "onPath": boolean, "requiresAuthorization": boolean]) { _, new in new })

    static var patches: Value {
        .object(["app": patch(ConfigurationService.appFields, inherits: false), "defaults": patch(ConfigurationService.launchFields, inherits: false), "instance": patch(ConfigurationService.launchFields, inherits: true)])
    }
    private static func patch(_ fields: [ConfigurationField], inherits: Bool) -> Value {
        var properties: [String: Value] = [:], groups: [String: [String: Value]] = [:]
        for field in fields {
            var schema: [String: Value] = ["type": .string(field.type)]
            if !field.values.isEmpty { schema["enum"] = .array(field.values.map(Value.string)) }
            if let minimum = field.minimum { schema["minimum"] = .integer(minimum) }
            if let maximum = field.maximum { schema["maximum"] = .integer(maximum) }
            let value = field.nullable ? nullable(.object(schema)) : .object(schema)
            properties[field.name] = value
            let components = field.name.split(separator: ".", maxSplits: 1).map(String.init)
            if components.count == 2 { groups[components[0], default: [:]][components[1]] = value }
        }
        for (group, children) in groups {
            var value = object(children).object!
            value["additionalProperties"] = .bool(false); value["minProperties"] = .integer(1)
            properties[group] = .object(value)
        }
        var set = object(properties).object!; set["additionalProperties"] = .bool(false)
        let reset = array(.object(["enum": .array(properties.keys.sorted().map(Value.string))]))
        let inherit = inherits ? array(.object(["enum": .array(ConfigurationService.groups.map(Value.string))])) : .object(["type": .string("array"), "maxItems": .integer(0)])
        var schema = object(["set": .object(set), "reset": reset, "inherit": inherit]).object!
        schema["additionalProperties"] = .bool(false)
        return .object(schema)
    }
    static func sideEffects(_ spec: CommandSpec) -> [String] {
        guard spec.mutation else { return [] }
        if let effects = ExperimentalCommandRegistry.sideEffects(spec) { return effects }
        switch spec.path.first {
        case "config": return ["configuration"]
        case "app": return ["preferences"]
        case "cli": return ["symlink"]
        case "account": return ["configuration", "credentials"]
        case "launch": return ["credentials", "downloads", "gameFiles", "process", "sessionHistory"]
        case "session": return spec.path.last == "export" ? ["exportFile"] : ["process"]
        case "download": return ["downloads", "exportFile"]
        case "cache": return ["downloads"]
        default: return ["configuration", "gameFiles"]
        }
    }

    static func input(_ spec: CommandSpec) -> Value {
        var options = Dictionary(uniqueKeysWithValues: spec.options.map { ($0.name, parameter($0)) })
        options.merge(["json": boolean, "output": .object(["enum": .array(["text", "json", "ndjson"].map(Value.string))]), "data-dir": string, "language": string, "quiet": boolean, "details": boolean,
                       "color": .object(["enum": .array(CommonOptions.colorModes.map(Value.string))])]) { old, _ in old }
        var optionSchema = object(options, required: spec.options.filter(\.required).map(\.name)).object!
        optionSchema["additionalProperties"] = .bool(false)
        var operands: [String: Value] = ["type": .string("array"), "minItems": .integer(spec.operands.filter(\.required).count), "maxItems": .integer(spec.operands.count)]
        if !spec.operands.isEmpty { operands["prefixItems"] = .array(spec.operands.map(parameter)) }
        return object(["operands": .object(operands), "options": .object(optionSchema)])
    }
    private static func parameter(_ p: ParameterSpec) -> Value {
        var result: [String: Value] = ["type": .string(["bool": "boolean", "int": "integer", "strings": "array"][p.type] ?? p.type), "description": .string(p.help)]
        if p.type == "strings" { result["items"] = string }
        if !p.values.isEmpty { result["enum"] = .array(p.values.map(Value.string)) }
        if p.name == "limit" { result["minimum"] = .integer(1); result["maximum"] = .integer(1000); result["default"] = .integer(50) }
        if p.name == "offset" { result["minimum"] = .integer(0); result["default"] = .integer(0) }
        if p.required && p.type == "strings" { result["minItems"] = .integer(1) }
        return .object(result)
    }
    static func result(_ spec: CommandSpec) -> Value {
        let error = object(["code": string, "message": string, "retryable": boolean, "nextActions": array(object(["command": array(string)], required: ["command"])), "details": .object([:])],
                           required: ["code", "message", "retryable", "nextActions", "details"])
        return object(["schemaVersion": .object(["const": .integer(1)]), "ok": boolean, "data": nullable(payload(spec)), "warnings": array(string), "error": nullable(error)],
                      required: ["schemaVersion", "ok", "data", "warnings", "error"])
    }
    static func payload(_ spec: CommandSpec) -> Value {
        if let result = ExperimentalCommandRegistry.schema(spec) { return result }
        let p = spec.path, action = p.last!, path = p.joined(separator: " ")
        if p.first == "config" {
            if action == "fields" {
                let field = object(fields("name,type,unit,group", type: nullable(string)).merging(["nullable": boolean, "sensitive": boolean, "values": array(string), "scopes": array(string), "minimum": nullable(integer), "maximum": nullable(integer)]) { _, n in n })
                return object(["scope": nullable(string), "prefix": nullable(string), "fields": array(field)])
            }
            return action == "get" ? configReport : object(["changed": boolean, "dryRun": boolean, "before": configReport, "after": configReport])
        }
        if path == "app info" { return object(fields("version,application,cli,dataDirectory", type: nullable(string)).merging(["schemaVersion": integer]) { _, n in n }) }
        if p.starts(with: ["app", "language"]) { return object(["language": string, "supported": array(string), "restartRequired": boolean, "dryRun": boolean]) }
        if path == "completions" { return object(["shell": string, "script": string]) }
        if p.first == "cli" { return action == "status" ? installation : object(["changed": boolean, "dryRun": boolean, "status": installation]) }
        if p.first == "cache" { return object(["bytes": integer, "files": integer].merging(action == "clean" ? ["dryRun": boolean] : [:]) { _, n in n }) }
        if path == "schema" { return object(["commands": array(object([:])), "output": object([:]), "globalOptions": array(string), "configuration": object([:])]) }
        if path == "doctor" { return object(["healthy": boolean, "checks": array(object(["check": string, "ok": boolean, "details": .object([:])]))]) }
        if action == "selected" { return object(["id": nullable(string)]) }
        if p.first == "catalog" {
            switch action {
            case "show": return object(["project": project, "description": string, "descriptionTruncated": boolean, "isHTML": boolean, "license": nullable(string)])
            case "categories": return page(object(fields("id,name,type")))
            default: return page(action == "versions" ? version : project)
            }
        }
        if p.first == "account" {
            if action == "list" { return page(account) }
            if action == "show" { return object(["account": account, "dryRun": boolean]) }
            if action == "add-offline" || action == "refresh" || action == "complete" { return object(["account": account, "dryRun": boolean]).mergingSchema(account) }
            if p.contains("service-key") { return object(["provider": string, "custom": boolean, "bundled": boolean, "dryRun": boolean]) }
            if action == "start" { return object(fields("flowID,verificationURL,userCode,expiresAt,server,selectedProfile", type: nullable(string)).merging(["profiles": array(object(fields("id,name"))), "userParticipation": boolean, "provider": string, "dryRun": boolean]) { _, n in n }) }
            return object(fields("id,action,flowID").merging(["dryRun": boolean, "removed": boolean, "cancelled": boolean]) { _, n in n })
        }
        if p.first == "session" {
            if action == "list" { return page(session) }
            if action == "logs" { return object(["sessionID": string, "text": string, "bounded": boolean]).mergingSchema(session) }
            if action == "quit" || action == "stop" { return object(["sessionID": string, "requested": string, "dryRun": boolean]) }
            if action == "diagnose" { return object(["sessionID": string, "summary": string, "facts": array(string), "findings": array(object(fields("id,title,explanation,confidence").merging(["steps": array(string), "actions": array(string), "evidence": array(object(["documentID": string, "line": integer, "excerpt": string]))]) { _, n in n })), "limitations": array(string)]) }
            if action == "export" { return object(["file": string, "dryRun": boolean, "files": array(object(["path": string, "bytes": integer, "redacted": boolean]))]) }
            return session
        }
        if p.first == "launch" { return session.mergingSchema(object(fields("instanceID,accountID,accountKind,javaPath,gameDirectory,command").merging(["javaMajor": integer, "authenticationChecked": boolean, "environmentNames": array(string), "dryRun": boolean]) { _, n in n })) }
        if p.first == "java" {
            if action == "list" { return page(object(["path": string, "managedID": nullable(string), "source": string, "runtime": nullable(java), "issue": nullable(string)])) }
            if action == "available" { return page(java) }
            if action == "references" { return page(string) }
            if action == "default" { return object(["changed": boolean, "dryRun": boolean, "before": configReport, "after": configReport]) }
            return java.mergingSchema(object(["runtime": java, "dryRun": boolean, "references": array(string), "trashedPath": nullable(string)]))
        }
        if p.first == "server" {
            let row = object(["id": .object(["anyOf": .array([integer, string])]), "name": string, "address": string, "resourcePacks": string, "validAddress": boolean,
                              "favorite": boolean, "saved": boolean, "instanceIDs": array(string), "notes": string, "preferredInstanceID": nullable(string)])
            if action == "list" { return page(row).mergingSchema(object(["warnings": array(string)])) }
            if action == "query" { return object(["address": string, "description": string, "version": nullable(string), "protocolVersion": nullable(integer), "online": nullable(integer), "maximum": nullable(integer), "latencyMilliseconds": nullable(integer), "playerSample": array(string), "queriedAt": string]) }
            return row.mergingSchema(object(["dryRun": boolean, "instanceID": string, "revision": string, "items": array(row)]))
        }
        if p.first == "world" {
            if action == "list" { return page(p.contains("backup") ? backup : world) }
            if action == "show" { return world }
            if action == "create" { return backup.mergingSchema(object(["dryRun": boolean, "world": .object(["anyOf": .array([world, nullable(string)])])])) }
            return object(fields("folder,action,file,removed", type: nullable(string)).merging(["dryRun": boolean, "world": world, "backup": backup, "replace": boolean]) { _, n in n })
        }
        if p.first == "schematic" {
            if action == "list" { return page(schematic) }
            return object(fields("name,author,description,target,directory,file", type: nullable(string)).merging(["entry": schematic, "dimensions": array(integer), "blocks": nullable(integer), "regions": nullable(integer), "formatVersion": nullable(integer), "gameDataVersion": nullable(integer), "dryRun": boolean]) { _, n in n })
        }
        if p.first == "datapack" {
            if action == "search" { return page(project).mergingSchema(object(["providerTotal": integer])) }
            if action == "versions" { return page(version) }
            if action == "list" { return page(object(["id": string, "enabled": boolean, "description": string, "error": nullable(string)])) }
            return object(["keys": array(string), "dryRun": boolean, "world": string, "name": string, "effectiveOnNextWorldLoad": boolean, "versions": array(version), "downloadBytes": integer])
        }
        if p.first == "content" {
            if action == "list" { return page(content) }
            return object(fields("action,file,kind").merging(["dryRun": boolean, "changed": boolean, "files": array(content.mergingSchema(object(["record": managed, "action": string]))),
                "updates": array(managed), "downloadBytes": integer, "project": project, "version": version, "manualFiles": array(object(["fileID": integer, "filename": string, "pageURL": string, "bytes": integer, "sha1": nullable(string), "md5": nullable(string)]))]) { _, n in n })
        }
        if p.first == "pack" || path == "instance import" {
            let pack = object(fields("instanceID,name,version,format,provider,projectID,versionID", type: nullable(string)).merging(["managedFiles": integer]) { _, n in n })
            return pack.mergingSchema(object(["dryRun": boolean, "instance": instance, "gameVersion": string, "files": integer, "bytes": integer, "manualFiles": array(object([:])), "curseForgeFiles": integer, "warnings": array(string),
                "packVersion": string, "author": string, "summary": string, "jvmArguments": string,
                "current": pack, "releases": array(object(["id": string, "title": string, "gameVersions": array(string), "publishedAt": nullable(string), "stable": boolean, "manualDownloadRequired": boolean, "pageURL": nullable(string)])),
                "changes": array(object(["path": string, "action": string, "conflict": boolean, "explanation": nullable(string)])), "offset": integer, "hasMore": boolean, "complete": boolean, "preservedFiles": integer, "available": boolean]))
        }
        if p.first == "directory" {
            if action == "list" { return page(directory) }
            if action == "scan" { return page(object(["id": string, "gameVersion": nullable(string), "issue": nullable(string), "components": array(object(fields("name,version"))), "locations": array(object(["id": string, "path": string, "available": boolean])), "suggestedLocation": nullable(string), "warnings": array(string)])) }
            return object(fields("id,path,name,layout,mode,customDirectory,source,target,copyIssue", type: nullable(string)).merging(["directories": array(directory), "selectedDirectoryID": nullable(string), "dryRun": boolean, "instances": array(string), "otherInstances": array(string), "sourceFiles": integer, "targetFiles": integer, "sourceBytes": integer, "targetBytes": integer, "canCopy": boolean]) { _, n in n })
        }
        if p.first == "recovery" {
            let entry = object(fields("kind,target,transaction,workspace,status,explanation,name,warning,preservedCopy", type: nullable(string)).merging(["nextAction": array(string), "committed": boolean, "canFinish": boolean, "dryRun": boolean]) { _, n in n })
            return action == "list" ? page(entry) : entry.mergingSchema(session)
        }
        if p.first == "download" { return object(["file": string, "dryRun": boolean, "verified": boolean]) }
        if path == "instance list" { return page(instance) }
        if path == "instance versions" { return page(object(fields("id,type"))) }
        if path == "instance component versions" { return page(string) }
        return instance.mergingSchema(object(["instance": instance, "dryRun": boolean, "instanceID": string, "source": string, "destination": string, "files": integer, "bytes": integer,
            "file": string, "warning": nullable(string), "preservedCopy": nullable(string), "preservedFiles": array(string), "retainedGameDirectory": nullable(string), "retainsExternalGameDirectory": boolean,
            "backup": nullable(string), "unavailableReason": nullable(string)]))
    }
}

private extension Value {
    func mergingSchema(_ other: Value) -> Value {
        var schema = object ?? [:]
        schema["properties"] = .object((self["properties"].object ?? [:]).merging(other["properties"].object ?? [:]) { _, new in new })
        return .object(schema)
    }
}
