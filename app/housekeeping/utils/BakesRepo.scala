package housekeeping.utils

import data.{ Bakes, Dynamo }
import models.{ Bake, BakeId, BakeStatus }

// Wrapper around dynamo access.
// Injecting this functionality as a class facilitates unit testing.
class BakesRepo(implicit dynamo: Dynamo) {

  def getBakes: List[Bake.DbModel] = Bakes.scanForAll()

  def updateStatusToTimedOutIfRunning(bakeId: BakeId): Unit = {
    // Couldn't work out how to specify that the instance should be running in the update request.
    // Therefore, look up the bake first and check its status.
    Bakes.findById(bakeId.recipeId, bakeId.buildNumber).foreach { bake =>
      if (bake.status == BakeStatus.Running) {
        Bakes.updateStatus(bakeId, BakeStatus.TimedOut)
      }
    }
  }
}