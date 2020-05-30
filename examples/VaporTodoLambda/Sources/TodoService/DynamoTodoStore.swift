import NIO
import DynamoDB
import AWSSDKSwiftCore

public class DynamoTodoStore {
  
  let dynamo   : DynamoDB
  let tableName: String
  let listName : String = "list"
  
  public init(
    eventLoopGroup: EventLoopGroup,
    tableName: String)
  {
    self.dynamo = DynamoDB(
      eventLoopGroupProvider: .shared(eventLoopGroup))
    self.tableName = tableName
  }

}

extension DynamoTodoStore: TodoStore {

  public func getTodos() -> EventLoopFuture<[TodoItem]> {
    return self.dynamo.query(.init(
      expressionAttributeValues: [":id" : .init(s: listName)],
      keyConditionExpression: "ListId = :id",
      tableName: tableName))
      .map { (output) -> ([TodoItem]) in
        return output.items!
          .compactMap { (attributes) -> TodoItem? in
            return TodoItem(attributes: attributes)
          }
          .sorted { (t1, t2) -> Bool in
            switch (t1.order, t2.order) {
            case (.none, .none):
              return false
            case (.some(_), .none):
              return true
            case (.none, .some(_)):
              return false
            case (.some(let o1), .some(let o2)):
              return o1 < o2
            }
          }
      }
  }
  
  public func getTodo(id: String) -> EventLoopFuture<TodoItem> {
    return self.dynamo.getItem(.init(key: ["ListId": .init(s: listName), "TodoId": .init(s: id)], tableName: tableName))
      .flatMapThrowing { (output) throws -> TodoItem in
        guard let attributes = output.item else {
          throw TodoError.notFound
        }
        guard let todo = TodoItem(attributes: attributes) else {
          throw TodoError.missingAttributes
        }
        return todo
      }
  }

  public func createTodo(_ todo: TodoItem) -> EventLoopFuture<TodoItem> {
    var attributes = todo.toDynamoItem()
    attributes["ListId"] = .init(s: self.listName)
    
    return self.dynamo.putItem(.init(item: attributes, tableName: tableName))
      .map { _ in
        return todo
      }
  }
  
  public func patchTodo(id: String, patch: PatchTodo) -> EventLoopFuture<TodoItem> {
    
    var updates: [String : DynamoDB.AttributeValueUpdate] = [:]
    if let title = patch.title {
      updates["Title"] = .init(action: .put, value: .init(s: title))
    }
    
    if let order = patch.order {
      updates["Order"] = .init(action: .put, value: .init(n: String(order)))
    }
    
    if let completed = patch.completed {
      updates["Completed"] = .init(action: .put, value: .init(bool: completed))
    }
    
    guard updates.count > 0 else {
      return self.getTodo(id: id)
    }
    
    let update = DynamoDB.UpdateItemInput(
      attributeUpdates: updates,
      key: ["ListId": .init(s: listName), "TodoId": .init(s: id)],
      returnValues: .allNew,
      tableName: tableName)
    
    return self.dynamo.updateItem(update)
      .flatMapThrowing { (output) -> TodoItem in
        guard let attributes = output.attributes else {
          throw TodoError.notFound
        }
        guard let todo = TodoItem(attributes: attributes) else {
          throw TodoError.missingAttributes
        }
        return todo
    }
  }
  
  public func deleteTodos(ids: [String]) -> EventLoopFuture<Void> {
    
    guard ids.count > 0 else {
      return self.dynamo.client.eventLoopGroup.next().makeSucceededFuture(Void())
    }
    
    let writeRequests = ids.map { (id) in
      DynamoDB.WriteRequest(deleteRequest: .init(key: ["ListId": .init(s: listName), "TodoId": .init(s: id)]))
    }

    return self.dynamo.batchWriteItem(.init(requestItems: [tableName : writeRequests]))
      .map { _ in }
  }
  
  public func deleteAllTodos() -> EventLoopFuture<Void> {
    return self.getTodos()
      .flatMap { (todos) -> EventLoopFuture<Void> in
        let ids = todos.map() { $0.id }
        return self.deleteTodos(ids: ids)
      }
  }
}
