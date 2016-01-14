plv8 = require('../../plpl/src/plv8')
crud = require('../../src/fhir/crud')
history = require('../../src/fhir/history')
schema = require('../../src/core/schema')

assert = require('assert')

copy = (x)-> JSON.parse(JSON.stringify(x))

describe "CORE: CRUD spec", ->
  before ->
    schema.fhir_create_storage(plv8, resourceType: 'Users')
    schema.fhir_create_storage(plv8, resourceType: 'Patient')

  beforeEach ->
    plv8.execute("SET plv8.start_proc = 'plv8_init'")
    schema.fhir_truncate_storage(plv8, resourceType: 'Users')
    schema.fhir_truncate_storage(plv8, resourceType: 'Patient')


  it "create", ->
    created = crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', name: 'admin'})
    assert.notEqual(created.id , false)
    assert.notEqual(created.meta.versionId, undefined)
    assert.equal(created.name, 'admin')


  it "conditional create", ->
    noise = crud.fhir_create_resource(plv8, resource: {resourceType: 'Patient', active: true})
    created = crud.fhir_create_resource(plv8,
      ifNoneExist: 'identifier=007'
      resource: {resourceType: 'Patient', identifier: [{value: '007'}], name: [{given: ['bond']}], active: true}
    )
    assert.notEqual(created.id , false)

    same = crud.fhir_create_resource(plv8,
      ifNoneExist: 'identifier=007'
      resource: {resourceType: 'Patient', identifier: [{value: '007'}], name: [{given: ['bond']}]}
    )
    assert.equal(same.id, created.id)

  it "create with allowed id", ->
    noise = crud.fhir_create_resource(plv8, resource: {resourceType: 'Patient', active: true})

    created = crud.fhir_create_resource(plv8,
      allowId: true
      resource: {resourceType: 'Patient', active: false, id: "test_id"}
    )
    assert.equal(created.id , "test_id")
    assert.equal(created.resourceType , "Patient")

    read = crud.fhir_read_resource(plv8, {id: "test_id", resourceType: 'Patient'})
    assert.equal(read.active, false)

  it "create with not allowed id", ->
    outcome = crud.fhir_create_resource(plv8, resource: {id: 'customid', resourceType: 'Users'})
    assert.equal(outcome.resourceType, 'OperationOutcome')
    assert.equal(outcome.issue[0].code, '400')

  it "handle version id, issue #57", ->
    res = crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', meta: {versionId: 'ups', lastUpdated: '1900-01-01'}})
    assert.notEqual(res.meta.versionId, 'ups')
    assert.notEqual(res.meta.lastUpdated, '1900-01-01')
    # just should not throw error
    crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', meta: {versionId: 'ups'}})

  it "create by update", ->
    created = crud.fhir_update_resource(plv8,
      resource: {resourceType: 'Patient', active: false, id: "pt_id"}
    )
    assert.equal(created.id , "pt_id")
    assert.equal(created.resourceType , "Patient")
    
    crud.fhir_delete_resource(plv8, {id: 'pt_id', resourceType: 'Patient'})

    updated = crud.fhir_update_resource(plv8,
      resource: {resourceType: 'Patient', active: true, id: "pt_id"}
    )

    assert.equal(updated.id , "pt_id")
    assert.equal(updated.resourceType , "Patient")

    read = crud.fhir_read_resource(plv8, {id: "pt_id", resourceType: 'Patient'})
    assert.equal(read.active, true)

  it "read", ->
    created = crud.fhir_create_resource(plv8, resource:  {resourceType: 'Users', name: 'admin'})
    read = crud.fhir_read_resource(plv8, {id: created.id, resourceType: 'Users'})
    assert.equal(read.id, created.id)

    read.versionId = read.meta.versionId
    vread = crud.fhir_vread_resource(plv8, read)
    assert.equal(read.id, vread.id)
    assert.equal(read.meta.versionId, vread.meta.versionId)

  it "read unexisting", ->
    read = crud.fhir_read_resource(plv8, {id: 'unexisting', resourceType: 'Users'})
    assert.equal(read.resourceType, 'OperationOutcome')
    issue = read.issue[0]
    assert.equal(issue.severity, 'error')
    assert.equal(issue.code, 'not-found')
    assert.equal(issue.details.coding[0].code, 'MSG_NO_EXIST')
    assert.equal(
      issue.details.coding[0].display,
      'Resource Id "unexisting" does not exist'
    )
    assert.equal(issue.diagnostics, 'Resource Id "unexisting" does not exist')

  it "vread unexisting", ->
    vread = crud.fhir_vread_resource(
      plv8,
      {
        id: 'unexistingId',
        versionId: 'unexistingVersionId',
        resourceType: 'Users'
      }
    )
    assert.equal(vread.resourceType, 'OperationOutcome')
    issue = vread.issue[0]
    assert.equal(issue.severity, 'error')
    assert.equal(issue.code, 'not-found')
    assert.equal(issue.details.coding[0].code, 'MSG_NO_EXIST')
    assert.equal(
      issue.details.coding[0].display,
      'Resource Id "unexistingId" does not exist'
    )
    assert.equal(
      issue.diagnostics,
      'Resource Id "unexistingId" with versionId "unexistingVersionId" does not exist'
    )

  it 'vread created', ->
    created = crud.fhir_create_resource(
      plv8,
      resource: {resourceType: 'Users', name: 'John Doe'}
    )
    created.versionId = created.meta.versionId
    vread = crud.fhir_vread_resource(plv8, created)
    assert.equal(
      (
        vread.meta.extension.filter (e) -> e.url == 'fhir-request-method'
      )[0].valueString,
      'POST'
    )
    assert.equal(
      (
        vread.meta.extension.filter (e) -> e.url == 'fhir-request-uri'
      )[0].valueUri,
      'Users'
    )

  it "update", ->
    created = crud.fhir_create_resource(plv8, resource:  {resourceType: 'Users', name: 'admin'})
    read = crud.fhir_read_resource(plv8, {id: created.id, resourceType: 'Users'})
    to_update = copy(read)
    to_update.name = 'changed'

    updated = crud.fhir_update_resource(plv8, resource: to_update)
    assert.equal(updated.name, to_update.name)
    assert.notEqual(updated.meta.versionId, false)
    assert.notEqual(updated.meta.versionId, read.meta.versionId)


    read_updated = crud.fhir_read_resource(plv8, updated)
    assert.equal(read_updated.name, to_update.name)
    # assert.equal(read_updated.meta.request.method, 'PUT')

    hx  = history.fhir_resource_history(plv8, {id: read.id, resourceType: 'Users'})
    assert.equal(hx.total, 2)
    assert.equal(hx.entry.length, 2)

    delete to_update.meta
    to_update.name = 'udpated without meta'

    updated = crud.fhir_update_resource(plv8, resource: to_update)
    assert.equal(updated.name, to_update.name)
    assert.notEqual(updated.meta.versionId, false)
    assert.notEqual(updated.meta.versionId, read.meta.versionId)

  it "update unexisting", ->
    updated = crud.fhir_update_resource(plv8, resource: {resourceType: "Users", id: "unexisting"})
    assert.equal(updated.id, 'unexisting')

  it "conditional update", ->
    noise = crud.fhir_create_resource(plv8, resource: {resourceType: 'Patient', active: true})
    created = crud.fhir_update_resource(plv8,
      resource:  {resourceType: 'Patient', identifier: [{value: '007'}]}
      queryString: 'identifier=007'
    )
    assert.equal(created.identifier[0].value, '007')
    assert.notEqual(noise.id, created.id)
    updated = crud.fhir_update_resource(plv8,
      resource:  {resourceType: 'Patient', identifier: [{value: '007'}], active: true}
      queryString: 'identifier=007'
    )
    assert.equal(created.id, updated.id)
    assert.equal(updated.active, true)

    outcome = crud.fhir_update_resource(plv8,
      resource:  {resourceType: 'Patient', identifier: [{value: '007'}], active: true}
      queryString: 'active=true'
    )
    assert.equal(outcome.resourceType, 'OperationOutcome')

  it "Update Resource Contention", ->
    created = crud.fhir_create_resource(plv8, resource:  {resourceType: 'Patient', identifier: [{value: '007'}]})
    updated = crud.fhir_update_resource(plv8,
      resource:  {id: created.id, resourceType: 'Patient', identifier: [{value: '007'}], active: true}
      ifMatch: created.meta.versionId
    )
    assert.equal(updated.resourceType, 'Patient')
    assert.equal(updated.active, true)
    outcome = crud.fhir_update_resource(plv8,
      resource:  {id: created.id, resourceType: 'Patient', identifier: [{value: '007'}], active: true}
      ifMatch: created.meta.versionId
    )
    assert.equal(outcome.resourceType, 'OperationOutcome')

  it "Update without id", ->
    outcome = crud.fhir_update_resource(plv8, resource:  {resourceType: 'Patient'})
    assert.equal(outcome.resourceType, 'OperationOutcome')
    assert.equal(outcome.issue[0].code, '400')

  it "Update with non existing id and meta should not fail", ->
    created = crud.fhir_update_resource(plv8, resource:  {id: 'nooonexisting', resourceType: 'Patient', meta: {versionId: 'dummy'}})
    assert.notEqual(created.meta.versionId, 'dummy')

  it 'vread updated', ->
    created = crud.fhir_create_resource(
      plv8,
      resource: {resourceType: 'Users', name: 'John Doe'}
    )

    read = crud.fhir_read_resource(plv8, {id: created.id, resourceType: 'Users'})
    to_update = copy(read)
    to_update.name = 'changed'

    updated = crud.fhir_update_resource(plv8, resource: to_update)
    updated.versionId = updated.meta.versionId
    vread = crud.fhir_vread_resource(plv8, updated)
    assert.equal(
      (
        vread.meta.extension.filter (e) -> e.url == 'fhir-request-method'
      )[0].valueString,
      'PUT'
    )
    assert.equal(
      (
        vread.meta.extension.filter (e) -> e.url == 'fhir-request-uri'
      )[0].valueUri,
      'Users'
    )

  it "delete", ->
    created = crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', name: 'admin'})
    read = crud.fhir_read_resource(plv8, {id: created.id, resourceType: 'Users'})

    deleted = crud.fhir_delete_resource(plv8, {id: read.id, resourceType: 'Users'})
    # assert.equal(deleted.meta.request.method, 'DELETE')

    hx_deleted  = history.fhir_resource_history(plv8, {id: read.id, resourceType: 'Users'})
    assert.equal(hx_deleted.total, 2)
    assert.equal(hx_deleted.entry.length, 2)

    read_deleted = crud.fhir_read_resource(plv8, {id: created.id, resourceType: 'Users'})
    assert.equal(read_deleted.resourceType, 'OperationOutcome')
    issue = read_deleted.issue[0]
    assert.equal(issue.severity, 'error')
    assert.equal(issue.code, 'not-found')

  it "delete unexisting", ->
    outcome = crud.fhir_delete_resource(plv8, {id: 'unexisting_id', resourceType: 'Users'})
    assert.equal(outcome.resourceType, 'OperationOutcome')
    assert.equal(outcome.issue[0].code, 'not-found')

  it "history", ->
    created = crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', name: 'admin'})
    read = crud.fhir_read_resource(plv8, {id: created.id, resourceType: 'Users'})

    deleted = crud.fhir_delete_resource(plv8, {id: read.id, resourceType: 'Users'})
    # assert.equal(deleted.meta.request.method, 'DELETE')

    hx_deleted  = history.fhir_resource_history(plv8, {id: read.id, resourceType: 'Users'})
    assert.equal(hx_deleted.total, 2)
    assert.equal(hx_deleted.entry.length, 2)

    read_deleted = crud.fhir_read_resource(plv8, {id: created.id, resourceType: 'Users'})
    assert.equal(read_deleted.resourceType, 'OperationOutcome')
    issue = read_deleted.issue[0]
    assert.equal(issue.severity, 'error')
    assert.equal(issue.code, 'not-found')

  it 'vread deleted', ->
    created = crud.fhir_create_resource(
      plv8,
      allowId: true
      resource: {id: 'toBeDeleted', resourceType: 'Users', name: 'John Doe'}
    )
    deleted = crud.fhir_delete_resource(
      plv8,
      {id: 'toBeDeleted', resourceType: 'Users'}
    )
    deleted.versionId = deleted.meta.versionId
    vread = crud.fhir_vread_resource(plv8, deleted)
    assert.equal(vread.resourceType, 'OperationOutcome')
    issue = vread.issue[0]
    assert.equal(issue.severity, 'error')
    assert.equal(issue.code, 'not-found')
    assert.equal(issue.details.coding[0].code, 'MSG_DELETED_ID')
    assert.equal(
      issue.details.coding[0].display,
      'The resource "toBeDeleted" has been deleted'
    )
    assert.equal(
      issue.diagnostics
      "Resource Id \"toBeDeleted\" with versionId \"#{deleted.versionId}\" has been deleted"
    )

  it "parse_history_params", ->
    [res, errors] = history.parse_history_params('_since=2010&_count=10')
    assert.deepEqual(res, {_since: '2010-01-01', _count: 10})

  it "resource type history", ->
    schema.fhir_truncate_storage(plv8, resourceType: 'Users')
    crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', name: 'u1'})
    crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', name: 'u2'})
    crud.fhir_create_resource(plv8, resource: {resourceType: 'Users', name: 'u3'})

    res = history.fhir_resource_type_history(plv8, resourceType: 'Users')
    assert.equal(res.total, 3)

    res = history.fhir_resource_type_history(plv8, resourceType: 'Users', queryString: "_count=2&_since=2015-11")
    assert.equal(res.total, 2)
