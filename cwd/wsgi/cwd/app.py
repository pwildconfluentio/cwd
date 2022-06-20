import json
import uuid
import os

from flask import Flask, render_template, request, abort, make_response, session, redirect
from flask_cors import CORS
from werkzeug.middleware.proxy_fix import ProxyFix
from random import seed
from random import randint

from confluent_kafka import Producer, KafkaError


from utils import set_finished, get_answer, word_is_valid, id_or_400, get_answer_info
from sql import get_sql
import datetime

here = os.path.dirname(__file__)

# Load Confluent ads
ad_file = os.path.join(here, "adcontent.txt")

with open(ad_file, encoding="utf8") as adfile:
    addata = adfile.readlines()
    addata = [ad.rstrip() for ad in addata]

# Create Producer instance
###PRODUCER START###
###PRODUCER END###


# Define topic names
registrations = "registrations"
guesstopic = "guesses"
game = "game"

def acked(err, msg):
    if err is not None:
        print("Failed to deliver message: {}".format(err))

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1)
CORS(app)
app.secret_key = 'Stream For Me'

def nowtime():
    return datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S %Z")


def api_response(json_data):
    resp = make_response(json.dumps(json_data))
    resp.content_type = "application/json; charset=utf-8"
    return resp


@app.context_processor
def inject_debug():
    return dict(debug=app.debug)


# Frontend views

@app.route("/")
@app.route("/play")
def index():
    if 'username' in session:
        username = session['username']
        if 'game' in session:
            if session['game'] != 'ended' and session['tries'] > 0:
                session['winstreak'] = 0
            session['game'] = 'started'
        return render_template("index.html")
    else:
        return redirect("/register")

@app.route("/random_a")
def random_a():
    adnumber = randint(0, len(addata)-1)
    a,b,c=addata[adnumber].split(",")
    return render_template("random_a.html", image=a, text=b, link=c)


@app.route('/endsession')
def logout():
    # remove the username from the session if it is there
    session.clear()
    return redirect("/register")

@app.route('/help')
def help():
    if 'username' in session:
        username = session['username']
        return render_template('help.html')
    else:
        return render_template('register.html')



@app.route("/register", methods=['GET', 'POST'])
def register():

    if 'username' in session:
        username = session['username']
        return redirect("/help")
    else:
        if request.method == 'POST':
            data = {}
            data['firstname'] = request.form.get('firstname')
            data['lastname'] = request.form.get('lastname')
            data['jobtitle'] = request.form.get('jobtitle')
            data['company'] = request.form.get('company')
            data['workemail'] = request.form.get('workemail')
            data['mobile'] = request.form.get('mobile')
            data['consent'] = request.form.get('consent')
            data['timestamp'] = nowtime()
            session.permanent = True
            session['username'] = request.form['mobile']
            session['winstreak'] = 0
            session['tries'] = 0
            session['avgtries'] = 0
            session['game'] = 'newplayer'


            message = json.dumps(data)


            def acked(err, msg):
                if err is not None:
                    print("Failed to deliver message: {}".format(err))

            record_key = data['mobile']
            record_value = message
            producer.produce(registrations, key=record_key, value=record_value, on_delivery=acked)


            return redirect("/help")
        else:
            return render_template('register.html')




# API endpoints
@app.route("/api/v1/start_game/", methods=["POST"])
def start_game():
  if 'username' in session:
    username = session['username']
    if 'game' in session:
        if session['game'] != 'ended' and session['tries'] >0:
            session['game'] = 'started'
            session['winstreak'] = 0
            session['avgtries'] = 0

    """
    Starts a new game
    """
    word_id = None
    try:
        word_id = int(request.json["wordID"])
        # PW added in so no one can replay a game
        word_id = None
    except (KeyError, TypeError, ValueError):
        pass
    con, cur = get_sql()
    key = str(uuid.uuid4())
    word_id, word = get_answer_info(word_id)
    cur.execute("""INSERT INTO game (word, key) VALUES (?, ?)""", (word, key))
    con.commit()
    con.close()
    return api_response({"id": cur.lastrowid, "key": key, "wordID": word_id})
  else:
    return redirect("/register")



@app.route("/api/v1/guess/", methods=["POST"])
def guess_word():
  if 'username' in session:
    username = session['username']
    try:
        guess = request.get_json(force=True)["guess"]
        assert len(guess) == 5
        assert guess.isalpha()
        assert word_is_valid(guess)
    except AssertionError:
        return abort(400, "Invalid word")
    game_id = id_or_400(request)
    con, cur = get_sql()
    cur.execute(
        """SELECT word, guesses, finished FROM game WHERE id = (?)""", (game_id,)
    )
    answer, guesses, finished = cur.fetchone()

    guesses = guesses.split(",")

    if len(guesses) > 6 or finished:
        return abort(403)
    guesses.append(guess)
    guesses = ",".join(guesses)
    if guesses[0] == ",":
        guesses = guesses[1:]
    tries = len(guesses.split(","))
    cur.execute("""UPDATE game SET guesses = (?) WHERE id = (?)""", (guesses, game_id))
    con.commit()
    con.close()
    guess_status = []
    guessed_letters = []
    for g_pos, g_char in enumerate(guess):
        status_int = 0
        if g_char in answer and (answer.count(g_char) > guessed_letters.count(g_char)):
            status_int += 1
            for a_pos, a_char in enumerate(answer):
                if g_char == a_char and g_pos == a_pos:
                    guessed_letters += g_char
                    status_int += 1
        guess_status.append(
            {
                "letter": g_char,
                "state": status_int,
            }
        )
    data = {}
    data['username'] = username
    data['game_id'] = game_id
    data['guess'] = guess
    data['answer'] = answer
    data['tries'] = tries
    data['win'] = str(bool(guess == answer))
    data['timestamp'] = nowtime()

    session['tries'] = tries

    message = json.dumps(data)
    record_key = str(game_id)
    record_value = message
    producer.produce(guesstopic, key=record_key, value=record_value, on_delivery=acked)

    if (guess == answer or tries == 6):
        if guess == answer:
            winstreak = session['winstreak'] + 1
            session['avgtries'] = (tries + (session['avgtries'] * (winstreak - 1))) / winstreak
        else:
            winstreak = 0
            session['avgtries'] = 0
        session['winstreak'] = winstreak
        session['tries'] = 0
        session['game'] = 'ended'

        data = {}
        data['username'] = username
        data['game_id'] = game_id
        data['answer'] = answer
        data['tries'] = tries
        data['winstreak'] = winstreak
        data['avgtries'] = session['avgtries']
        data['timestamp'] = nowtime()

        message = json.dumps(data)
        record_key = str(game_id)
        record_value = message
        producer.produce(game, key=record_key, value=record_value, on_delivery=acked)
    return api_response(guess_status)
  else:
    return redirect("/register")


@app.route("/api/v1/finish_game/", methods=["POST"])
def finish_game():
  if 'username' in session:
    username = session['username']
    game_id = id_or_400(request)
    set_finished(game_id)
    answer = get_answer(game_id)
    return api_response({"answer": answer})
  else:
    return redirect("/register")



if __name__ == "__main__":
    app.run()
